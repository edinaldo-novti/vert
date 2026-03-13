# frozen_string_literal: true

module Vert
  module Rls
    class ConnectionHandler
      class << self
        def set_context(tenant_id:, company_id: nil, user_id: nil)
          return unless tenant_id.present?
          connection = ActiveRecord::Base.connection
          connection.execute(ActiveRecord::Base.sanitize_sql(["SET LOCAL app.current_tenant_id = %s", tenant_id]))
          connection.execute(ActiveRecord::Base.sanitize_sql(["SET LOCAL app.current_company_id = %s", company_id])) if company_id.present?
          connection.execute(ActiveRecord::Base.sanitize_sql(["SET LOCAL app.current_user_id = %s", user_id])) if user_id.present?
          Vert::Current.rls_configured = true
        rescue StandardError => e
          Rails.logger.error("[Vert::RLS] #{e.message}") if defined?(Rails)
          raise
        end

        def reset_context
          return unless Vert::Current.rls_configured
          connection = ActiveRecord::Base.connection
          connection.execute("RESET app.current_tenant_id")
          connection.execute("RESET app.current_company_id")
          connection.execute("RESET app.current_user_id")
          Vert::Current.rls_configured = false
        rescue StandardError => e
          Rails.logger.error("[Vert::RLS] #{e.message}") if defined?(Rails)
        end

        def with_context(tenant_id:, company_id: nil, user_id: nil)
          previous = Vert::Current.serialize
          set_context(tenant_id: tenant_id, company_id: company_id, user_id: user_id)
          Vert::Current.set_context(tenant_id: tenant_id, company_id: company_id, user_id: user_id)
          yield
        ensure
          reset_context
          Vert::Current.deserialize(previous)
        end

        def create_functions_sql
          <<~SQL
            CREATE OR REPLACE FUNCTION current_tenant_id() RETURNS uuid AS $$
              SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::uuid;
            $$ LANGUAGE SQL STABLE;
            CREATE OR REPLACE FUNCTION current_company_id() RETURNS uuid AS $$
              SELECT NULLIF(current_setting('app.current_company_id', true), '')::uuid;
            $$ LANGUAGE SQL STABLE;
            CREATE OR REPLACE FUNCTION current_user_id() RETURNS uuid AS $$
              SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid;
            $$ LANGUAGE SQL STABLE;
          SQL
        end
      end
    end
  end
end
