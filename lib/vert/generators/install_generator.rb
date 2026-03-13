# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

module Vert
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs Vert and generates configuration files"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/vert.rb"
      end

      def create_current_model
        template "current.rb.tt", "app/models/current.rb"
      end

      def create_application_record
        template "application_record.rb.tt", "app/models/application_record.rb"
      end

      def create_outbox_event_model
        template "outbox_event.rb.tt", "app/models/outbox_event.rb"
      end

      def create_outbox_migration
        migration_template "create_outbox_events.rb.tt",
                           "db/migrate/#{timestamp}_create_outbox_events.rb"
      end

      def create_health_controller
        template "health_controller.rb.tt", "app/controllers/health_controller.rb"
      end

      def add_routes
        route 'get "/health", to: "health#show"'
        route 'get "/health/live", to: "health#live"'
        route 'get "/health/ready", to: "health#ready"'
      end

      def show_instructions
        say "\n"
        say "Vert installed successfully!", :green
        say "\n"
        say "Next steps:", :yellow
        say "1. Edit config/initializers/vert.rb to enable the features you need"
        say "2. Run migrations: rails db:migrate"
        say "3. Include Vert concerns in your models as needed:"
        say "   include Vert::Concerns::UuidPrimaryKey"
        say "   include Vert::Concerns::MultiTenant"
        say "   include Vert::Concerns::Auditable"
        say "   include Vert::Concerns::SoftDeletable"
        say "\n"
      end

      private

      def timestamp
        Time.current.strftime("%Y%m%d%H%M%S")
      end
    end
  end
end
