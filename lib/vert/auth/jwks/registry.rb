# frozen_string_literal: true

require_relative "remote_set"

module Vert
  module Auth
    module Jwks
      # Registry
      # --------
      # Singleton memoized por URL, garantindo que múltiplos controllers
      # apontando para o mesmo `JWKS_URL` compartilhem o mesmo `RemoteSet`
      # (e portanto o mesmo cache HTTP).
      #
      # Thread-safe via Mutex.
      module Registry
        @mutex     = Mutex.new
        @instances = {}

        class << self
          # Retorna (criando se necessário) o RemoteSet para a URL informada.
          # Parâmetros adicionais (ttl/cooldown/timeout) são aplicados apenas
          # na primeira chamada — chamadas subsequentes ignoram (singleton).
          def for(url, **opts)
            raise ArgumentError, "url is required" if url.to_s.strip.empty?

            @mutex.synchronize do
              @instances[url] ||= RemoteSet.new(url: url, **opts)
            end
          end

          # Limpa o registry. Uso típico: teardown de testes.
          def reset!
            @mutex.synchronize { @instances.clear }
          end

          # Útil em testes: injetar um RemoteSet stub.
          def register(url, set)
            @mutex.synchronize { @instances[url] = set }
          end
        end
      end
    end
  end
end
