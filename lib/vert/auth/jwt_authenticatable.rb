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
    #   - `jwt_secret`           → default `ENV["JWT_SECRET"]`
    #   - `jwt_algorithm`        → default `ENV.fetch("JWT_ALGORITHM", "HS256")`
    #   - `tenant_header_name`   → default `"X-Tenant-ID"`
    #   - `on_tenant_mismatch`   → default só faz `Rails.logger.warn`. Cada
    #                              serviço pode override para gravar em
    #                              `audit_logs` / `security_events`.
    #   - `on_jwt_invalid`       → default `Rails.logger.warn`.
    #   - `current_jwt_user`     → default `nil`. Serviços que tenham model
    #                              `User` podem retornar o registro para uso
    #                              em controllers.
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

        ::JWT.decode(
          token,
          jwt_secret,
          true,
          algorithm: jwt_algorithm
        ).first
      rescue ::JWT::DecodeError, ::JWT::ExpiredSignature, ::JWT::VerificationError => e
        on_jwt_invalid(error: e)
        nil
      rescue LoadError
        Rails.logger.error("[Vert::Auth] gem 'jwt' não carregada — adicione `gem \"jwt\"` ao Gemfile do serviço")
        nil
      end

      def jwt_secret
        ENV.fetch("JWT_SECRET")
      end

      def jwt_algorithm
        ENV.fetch("JWT_ALGORITHM", "HS256")
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

      # Override no serviço para retornar o registro User correspondente
      # ao `sub` do JWT.
      def current_jwt_user
        nil
      end
    end
  end
end
