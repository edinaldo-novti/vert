# frozen_string_literal: true

module Vert
  module Rls
    class ContextMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        response = @app.call(env)
        response
      ensure
        Vert::Rls::ConnectionHandler.reset_context if Vert.config.enable_rls
      end
    end

    module ControllerContext
      extend ActiveSupport::Concern

      included do
        after_action :configure_rls_context, if: -> { Vert.config.enable_rls }
      end

      private

      def configure_rls_context
        return unless Vert::Current.tenant_id.present?
        Vert::Rls::ConnectionHandler.set_context(
          tenant_id: Vert::Current.tenant_id,
          company_id: Vert::Current.company_id,
          user_id: Vert::Current.user_id
        )
      end
    end
  end
end
