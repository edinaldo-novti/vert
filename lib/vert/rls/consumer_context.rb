# frozen_string_literal: true

module Vert
  module Rls
    module ConsumerContext
      extend ActiveSupport::Concern

      def work_with_params(message, delivery_info, metadata)
        h = metadata[:headers] || {}
        Vert::Current.set_context(
          tenant_id: h["tenant_id"] || h[:tenant_id],
          user_id: h["user_id"] || h[:user_id],
          company_id: h["company_id"] || h[:company_id],
          request_id: h["request_id"] || h[:request_id] || SecureRandom.uuid
        )
        if Vert.config.enable_rls && Vert::Current.tenant_id.present?
          ConnectionHandler.set_context(tenant_id: Vert::Current.tenant_id, company_id: Vert::Current.company_id, user_id: Vert::Current.user_id)
        end
        super
      ensure
        Vert::Current.reset_all
        ConnectionHandler.reset_context if Vert.config.enable_rls
      end
    end

    class BaseConsumer
      include Sneakers::Worker if defined?(Sneakers::Worker)
      include ConsumerContext if defined?(Sneakers::Worker)
    end
  end
end
