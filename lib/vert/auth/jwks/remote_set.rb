# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Vert
  module Auth
    module Jwks
      # RemoteSet
      # ---------
      # Cliente JWKS (RFC 7517) com cache TTL e cooldown em erro. Pega a chave
      # pública usada para verificar uma assinatura RS256 a partir do `kid`
      # do header JWT.
      #
      # Não pré-aquece no boot (evita dependência circular quando o serviço
      # que emite tokens é o próprio IAM): faz lazy fetch na primeira chamada
      # a `fetch_key` / `keys`.
      #
      # Thread-safe via Mutex. Cooldown em erro evita stampede contra o IAM.
      #
      # Uso:
      #
      #   set = Vert::Auth::Jwks::RemoteSet.new(url: "https://iam/.well-known/jwks.json")
      #   public_key = set.fetch_key(kid: "2026-05")
      #
      class RemoteSet
        class FetchError < StandardError; end
        class KeyNotFoundError < StandardError; end

        DEFAULT_CACHE_TTL  = 3600
        DEFAULT_COOLDOWN   = 30
        DEFAULT_TIMEOUT    = 5
        DEFAULT_MAX_RETRY  = 3

        def initialize(url:, cache_ttl: DEFAULT_CACHE_TTL, cooldown: DEFAULT_COOLDOWN,
                       http_timeout: DEFAULT_TIMEOUT, max_retry: DEFAULT_MAX_RETRY)
          raise ArgumentError, "url is required" if url.to_s.strip.empty?

          @url           = url
          @cache_ttl     = cache_ttl.to_i
          @cooldown      = cooldown.to_i
          @http_timeout  = http_timeout.to_i
          @max_retry     = max_retry.to_i
          @mutex         = Mutex.new
          @keys_by_kid   = {}
          @raw_keys      = []
          @cached_at     = nil
          @last_error_at = nil
        end

        # Retorna OpenSSL::PKey::RSA público para o kid informado.
        # Faz refresh on-demand se cache vencido. Levanta KeyNotFoundError
        # caso o kid não exista no JWKS atual — chamador pode optar por
        # chamar `refresh!` e tentar novamente (cobre rotação fresh).
        def fetch_key(kid:)
          raise ArgumentError, "kid is required" if kid.to_s.strip.empty?

          ensure_fresh!
          key = @mutex.synchronize { @keys_by_kid[kid] }
          return key if key

          raise KeyNotFoundError, "kid '#{kid}' not found in JWKS at #{@url}"
        end

        # Hash de JWKs brutos {kid => jwk_hash}. Útil para inspeção.
        def keys
          ensure_fresh!
          @mutex.synchronize { @raw_keys.dup }
        end

        # Força refetch ignorando TTL. Respeita cooldown em erro recente.
        def refresh!
          @mutex.synchronize do
            return if in_cooldown?

            fetch_and_parse_locked
          end
          true
        end

        private

        def ensure_fresh!
          @mutex.synchronize do
            return if cache_valid?
            return if in_cooldown? && @cached_at # serve stale dentro do cooldown

            fetch_and_parse_locked
          end
        end

        def cache_valid?
          return false if @cached_at.nil?

          (monotonic_now - @cached_at) < @cache_ttl
        end

        def in_cooldown?
          return false if @last_error_at.nil?

          (monotonic_now - @last_error_at) < @cooldown
        end

        def fetch_and_parse_locked
          body = http_get_with_retry
          parsed = JSON.parse(body)
          keys_array = parsed["keys"]
          raise FetchError, "JWKS response missing 'keys' array" unless keys_array.is_a?(Array)

          new_index = {}
          keys_array.each do |jwk|
            next unless jwk.is_a?(Hash) && jwk["kid"]

            new_index[jwk["kid"]] = jwk_to_rsa_public(jwk)
          end
          raise FetchError, "JWKS at #{@url} has no usable keys" if new_index.empty?

          @raw_keys      = keys_array
          @keys_by_kid   = new_index
          @cached_at     = monotonic_now
          @last_error_at = nil
        rescue StandardError => e
          @last_error_at = monotonic_now
          raise e if @cached_at.nil? # primeira tentativa: propaga

          # Em refresh subsequente, mantém cache anterior e apenas loga.
          warn("[Vert::Auth::Jwks] refresh failed (serving stale): #{e.class}: #{e.message}")
        end

        def http_get_with_retry
          attempt = 0
          begin
            attempt += 1
            http_get_jwks
          rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
            if attempt < @max_retry
              sleep(backoff_seconds(attempt))
              retry
            end
            raise FetchError, "JWKS fetch failed after #{attempt} attempts: #{e.class}: #{e.message}"
          end
        end

        def http_get_jwks
          uri = URI(@url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = @http_timeout
          http.read_timeout = @http_timeout

          req = Net::HTTP::Get.new(uri.request_uri, "Accept" => "application/json")
          res = http.request(req)

          unless res.is_a?(Net::HTTPSuccess)
            raise FetchError, "JWKS endpoint returned #{res.code} #{res.message}"
          end

          res.body.to_s
        end

        def jwk_to_rsa_public(jwk)
          require "jwt" unless defined?(::JWT)

          ::JWT::JWK.new(jwk).keypair
        rescue StandardError => e
          raise FetchError, "Failed to parse JWK kid=#{jwk['kid'].inspect}: #{e.class}: #{e.message}"
        end

        def backoff_seconds(attempt)
          # 1s, 2s, 4s, ...
          2**(attempt - 1)
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
