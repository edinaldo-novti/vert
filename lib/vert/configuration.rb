# frozen_string_literal: true

module Vert
  # Configuração central da gem. Todos os recursos são opcionais e ativados no initializer.
  #
  # @example config/initializers/vert.rb
  #   Vert.configure do |config|
  #     config.enable_rls = true
  #     config.enable_outbox = true
  #     config.enable_health = true
  #     config.rabbitmq_url = ENV["RABBITMQ_URL"]
  #   end
  class Configuration
    # --- Flags de funcionalidade (todos opcionais) ---
    attr_accessor :enable_rls,
                  :enable_outbox,
                  :enable_health,
                  :enable_authorization,
                  :enable_multi_tenant,
                  :enable_auditable,
                  :enable_soft_deletable,
                  :enable_uuid_primary_key,
                  :enable_company_scoped,
                  :enable_document_storeable

    # --- RLS (Row Level Security) ---
    attr_accessor :rls_user

    # --- RabbitMQ / Outbox ---
    attr_accessor :rabbitmq_url, :exchange_name

    # --- Document service client ---
    attr_accessor :document_service_url

    # --- Health ---
    attr_accessor :health_check_path, :auto_mount_health_routes,
                  :health_check_database, :health_check_redis,
                  :health_check_rabbitmq, :health_check_sidekiq

    def initialize
      # Funcionalidades desativadas por padrão; ative no initializer conforme necessário
      @enable_rls = false
      @enable_outbox = false
      @enable_health = true
      @enable_authorization = false
      @enable_multi_tenant = false
      @enable_auditable = false
      @enable_soft_deletable = false
      @enable_uuid_primary_key = false
      @enable_company_scoped = false
      @enable_document_storeable = false

      @rls_user = ENV.fetch("RLS_USER", "app_user")
      @rabbitmq_url = ENV.fetch("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
      @exchange_name = ENV.fetch("RABBITMQ_EXCHANGE", "vert.events")
      @document_service_url = ENV.fetch("DOCUMENT_SERVICE_URL", "http://localhost:3020")
      @health_check_path = "/health"
      @auto_mount_health_routes = false
      @health_check_database = true
      @health_check_redis = false
      @health_check_rabbitmq = false
      @health_check_sidekiq = false
    end
  end
end
