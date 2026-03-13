# frozen_string_literal: true

require_relative "vert/version"
require_relative "vert/configuration"

# Concerns (sempre carregados; inclua no model conforme necessário)
require_relative "vert/concerns/current_attributes"
require_relative "vert/concerns/uuid_primary_key"
require_relative "vert/concerns/auditable"
require_relative "vert/concerns/soft_deletable"
require_relative "vert/concerns/multi_tenant"
require_relative "vert/concerns/company_scoped"
require_relative "vert/concerns/document_storeable"

# Clients
require_relative "vert/clients/document_service_client"

# Outbox
require_relative "vert/outbox/event"
require_relative "vert/outbox/publisher"
require_relative "vert/outbox/publisher_job"

# RLS
require_relative "vert/rls/context_middleware"
require_relative "vert/rls/job_context"
require_relative "vert/rls/consumer_context"
require_relative "vert/rls/connection_handler"

# Health
require_relative "vert/health/checker"
require_relative "vert/health/routes"

# Authorization
require_relative "vert/authorization/permission_resolver"
require_relative "vert/authorization/dynamic_policy"
require_relative "vert/authorization/policy_finder"
require_relative "vert/authorization/controller_methods"

# Railtie
require_relative "vert/railtie" if defined?(Rails::Railtie)

module Vert
  class Error < StandardError; end
  class TenantNotSetError < Error; end
  class CompanyNotSetError < Error; end

  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Vert::Configuration.new
    end

    alias config configuration
  end
end
