# frozen_string_literal: true

module Vert
  class Railtie < Rails::Railtie
    config.vert = ActiveSupport::OrderedOptions.new

    initializer "vert.consumer_paths", before: :set_autoload_paths do |app|
      consumers_path = app.root.join("app", "consumers")
      if consumers_path.directory?
        app.config.autoload_paths << consumers_path
        app.config.eager_load_paths << consumers_path
      end
    end

    initializer "vert.middleware" do |app|
      if Vert.config.enable_rls
        app.middleware.use Vert::Rls::ContextMiddleware
      end
    end

    initializer "vert.sidekiq" do
      if defined?(Sidekiq) && Vert.config.enable_rls
        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add Vert::Rls::JobMiddleware
          end
        end
        Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add Vert::Rls::JobClientMiddleware
          end
        end
      end
    end

    config.to_prepare do
      if Vert.config.enable_rls && defined?(ApplicationController)
        ApplicationController.include(Vert::Rls::ControllerContext)
      end
    end

    initializer "vert.routes" do |app|
      next unless Vert.config.enable_health && Vert.config.auto_mount_health_routes
      next if app.routes.named_routes.key?(:health)

      app.routes.append do
        Vert::Health::Routes.mount(self)
      end
    end

    generators do
      require_relative "generators/install_generator"
      require_relative "generators/rls_migration_generator"
    end

    console do
      puts "Vert v#{Vert::VERSION} loaded"
      puts "  Config: Vert.config"
      puts "  Health: Vert::Health.check_all (when enable_health)"
    end
  end
end
