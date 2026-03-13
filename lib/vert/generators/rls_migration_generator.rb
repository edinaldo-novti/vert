# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

module Vert
  module Generators
    class RlsMigrationGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Generates PostgreSQL Row Level Security setup migration"

      class_option :tables, type: :array, default: [],
                            desc: "Tables to enable RLS on"

      def create_rls_functions_migration
        migration_template "create_rls_functions.rb.tt",
                           "db/migrate/#{timestamp}_create_rls_functions.rb"
      end

      def create_enable_rls_migration
        return if options[:tables].empty?

        migration_template "enable_rls_on_tables.rb.tt",
                           "db/migrate/#{next_timestamp}_enable_rls_on_tables.rb"
      end

      def show_instructions
        say "\n"
        say "RLS migrations generated!", :green
        say "\n"
        say "Next steps:", :yellow
        say "1. Run migrations: rails db:migrate"
        say "2. Set enable_rls = true in config/initializers/vert.rb"
        say "3. Ensure your database user has appropriate privileges"
        say "\n"
        say "To enable RLS on additional tables, run:", :cyan
        say "  rails generate vert:rls_migration --tables orders invoices"
        say "\n"
      end

      private

      def timestamp
        @timestamp ||= Time.current.strftime("%Y%m%d%H%M%S")
      end

      def next_timestamp
        @next_timestamp ||= (Time.current + 1.second).strftime("%Y%m%d%H%M%S")
      end

      def tables_list
        options[:tables]
      end
    end
  end
end
