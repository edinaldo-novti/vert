# frozen_string_literal: true

module Vert
  module Auth
    # JwtAuthenticatable
    # ------------------
    # Concern para controllers Rails que autenticam via JWT Bearer e estabelecem
    # contexto multi-tenant através de Vert::Current.
    #
    # Política de segurança (regra invioláv. 2 do projeto):
    # - tenant_id, company_id e user_id SÃO LIDOS APENAS DO JWT.
    # - O header `X-Tenant-ID`, quando presente, é tratado como defesa em
    #   profundidade: precisa ser igual ao `tenant_id` do JWT, senão a request
    #   é rejeitada com 403 (potencial tentativa cross-tenant).
    # - Se o header estiver ausente, o JWT manda silenciosamente.
    #
    # Uso típico:
    #
    #   # config/initializers/vert.rb
    #   Vert.configure { |c| c.enable_jwt_auth = true }
    #
    #   # app/controllers/api/base_controller.rb
    #   class Api::BaseController < ApplicationController
    #     include Vert::Auth::JwtAuthenticatable
    #   end
    #
    # Opt-out por controller:
    #
    #   class Api::PublicController < Api::BaseController
    #     skip_jwt_authentication
    #   end
    #
    # Hooks override-áveis (por serviço):
    #
    #   - `jwt_secret`           → default `ENV["JWT_SECRET"]` (usado só em HS*)
    #   - `jwt_algorithm`        → default `ENV.fetch("JWT_ALGORITHM", "HS256")`
    #   - `jwks_url`             → default `ENV["JWKS_URL"]` (obrigatório em RS*/ES*/PS*)
    #   - `expected_issuer`      → default `ENV["JWT_EXPECTED_ISSUER"]` (verificado em RS*/ES*/PS*)
    #   - `tenant_header_name`   → default `"X-Tenant-ID"`
    #   - `on_tenant_mismatch`   → default só faz `Rails.logger.warn`. Cada
    #                              serviço pode override para gravar em
    #                              `audit_logs` / `security_events`.
    #   - `on_jwt_invalid`       → default `Rails.logger.warn`.
    #   - `current_jwt_user`     → default `nil`. Serviços que tenham model
    #                              `User` podem retornar o registro para uso
    #                              em controllers.
    #
    # Algoritmos assimétricos suportados: RS256/RS384/RS512, ES256/ES384/ES512,
    # PS256/PS384/PS512. Para usá-los, configure `JWT_ALGORITHM=RS256` (ou similar)
    # e `JWKS_URL=https://iam.example.com/.well-known/jwks.json`. O serviço busca
    # a chave pública via JWKS pelo `kid` do header do token.
    module JwtAuthenticatable
      extend ActiveSupport::Concern

      class Error < StandardError; end
      class MissingTokenError < Error; end
      class InvalidTokenError < Error; end
      class TenantMismatchError < Error; end

      included do
        before_action :authenticate_jwt!
      end

      class_methods do
        # Permite que um controller filho opt-out do filtro
        # (ex: endpoints públicos como /auth/sign_in, /health).
        def skip_jwt_authentication(**options)
          skip_before_action :authenticate_jwt!, **options
        end
      end

      private

      def authenticate_jwt!
        token = extract_bearer_token
        if token.blank?
          render_jwt_error(:unauthorized, "Missing authorization token")
          return
        end

        @jwt_payload = decode_jwt(token)
        if @jwt_payload.nil?
          render_jwt_error(:unauthorized, "Invalid or expired token")
          return
        end

        jwt_tenant_id   = @jwt_payload["tenant_id"]
        header_tenant   = request.headers[tenant_header_name].presence

        if header_tenant.present? && jwt_tenant_id.present? &&
           header_tenant.to_s != jwt_tenant_id.to_s
          on_tenant_mismatch(
            jwt_tenant_id: jwt_tenant_id,
            header_tenant_id: header_tenant,
            user_id: @jwt_payload["sub"]
          )
          render_jwt_error(:forbidden, "Tenant header mismatch")
          return
        end

        Vert::Current.set_context(
          tenant_id:  jwt_tenant_id,
          company_id: @jwt_payload["company_id"],
          user_id:    @jwt_payload["sub"],
          request_id: request.request_id
        )

        true
      end

      def extract_bearer_token
        header = request.headers["Authorization"]
        return nil unless header.is_a?(String) && header.start_with?("Bearer ")

        header.split(" ", 2).last.to_s.strip.presence
      end

      def decode_jwt(token)
        require "jwt" unless defined?(JWT)

        if asymmetric_algorithm?
          decode_jwt_asymmetric(token)
        else
          decode_jwt_symmetric(token)
        end
      rescue ::JWT::DecodeError, ::JWT::ExpiredSignature, ::JWT::VerificationError,
             ::JWT::InvalidIssuerError => e
        on_jwt_invalid(error: e)
        nil
      rescue LoadError
        Rails.logger.error("[Vert::Auth] gem 'jwt' não carregada — adicione `gem \"jwt\"` ao Gemfile do serviço")
        nil
      end

      def decode_jwt_symmetric(token)
        ::JWT.decode(
          token,
          jwt_secret,
          true,
          algorithm: jwt_algorithm
        ).first
      end

      def decode_jwt_asymmetric(token)
        url = jwks_url
        if url.to_s.strip.empty?
          on_jwt_invalid(error: RuntimeError.new("JWKS_URL ausente para algoritmo #{jwt_algorithm}"))
          return nil
        end

        kid = extract_kid_from_token(token)
        if kid.to_s.strip.empty?
          on_jwt_invalid(error: ::JWT::DecodeError.new("header sem 'kid' — RS*/ES*/PS* exigem kid"))
          return nil
        end

        registry = Vert::Auth::Jwks::Registry.for(url)
        decode_with_kid(token, registry, kid)
      end

      def jwt_secret
        ENV.fetch("JWT_SECRET")
      end

      def jwt_algorithm
        ENV.fetch("JWT_ALGORITHM", "HS256")
      end

      def jwks_url
        ENV["JWKS_URL"]
      end

      def expected_issuer
        ENV["JWT_EXPECTED_ISSUER"]
      end

      def asymmetric_algorithm?
        alg = jwt_algorithm.to_s
        alg.start_with?("RS", "ES", "PS")
      end

      def extract_kid_from_token(token)
        # Decode sem verificar assinatura (só queremos o header).
        _, header = ::JWT.decode(token, nil, false)
        header && header["kid"]
      rescue ::JWT::DecodeError
        nil
      end

      def decode_with_kid(token, registry, kid, retried: false)
        public_key = registry.fetch_key(kid: kid)
        verify_opts = jwt_verify_options
        ::JWT.decode(token, public_key, true, verify_opts).first
      rescue Vert::Auth::Jwks::RemoteSet::KeyNotFoundError => e
        # Pode ser rotação fresh — força refresh do JWKS e tenta 1x mais.
        if retried
          on_jwt_invalid(error: e)
          return nil
        end

        begin
          registry.refresh!
        rescue Vert::Auth::Jwks::RemoteSet::FetchError => fetch_err
          on_jwt_invalid(error: fetch_err)
          return nil
        end
        decode_with_kid(token, registry, kid, retried: true)
      rescue Vert::Auth::Jwks::RemoteSet::FetchError => e
        on_jwt_invalid(error: e)
        nil
      end

      def jwt_verify_options
        opts = { algorithm: jwt_algorithm }
        iss = expected_issuer
        if iss && !iss.to_s.strip.empty?
          opts[:iss] = iss
          opts[:verify_iss] = true
        end
        opts
      end

      def tenant_header_name
        "X-Tenant-ID"
      end

      # Hook: chamado quando header X-Tenant-ID diverge do JWT.
      # Override em ApplicationController para gravar em audit_logs:
      #
      #   def on_tenant_mismatch(jwt_tenant_id:, header_tenant_id:, user_id:)
      #     super
      #     AuditLog.create!(
      #       event_type: "security.tenant_mismatch",
      #       user_id: user_id,
      #       payload: { jwt_tenant_id:, header_tenant_id:, ip: request.remote_ip, path: request.fullpath }
      #     )
      #   end
      def on_tenant_mismatch(jwt_tenant_id:, header_tenant_id:, user_id:)
        Rails.logger.warn(
          "[Vert::Auth] Tenant mismatch: " \
          "user=#{user_id} jwt=#{jwt_tenant_id} header=#{header_tenant_id} " \
          "ip=#{request.remote_ip} path=#{request.fullpath}"
        )
      end

      def on_jwt_invalid(error:)
        Rails.logger.warn("[Vert::Auth] JWT decode error: #{error.class}: #{error.message}")
      end

      def render_jwt_error(status, message)
        render json: { error: message }, status: status
      end

      # Payload bruto do JWT (claims), disponível nos controllers
      # após `authenticate_jwt!`.
      def current_jwt_payload
        @jwt_payload
      end

      # True após `authenticate_jwt!` ter populado o payload com sucesso.
      # Útil para `before_action :foo, if: :jwt_authenticated?` em callbacks
      # que dependem de Vert::Current já populado.
      def jwt_authenticated?
        @jwt_payload.present?
      end

      # Override no serviço para retornar o registro User correspondente
      # ao `sub` do JWT.
      def current_jwt_user
        nil
      end
    end
  end
end
