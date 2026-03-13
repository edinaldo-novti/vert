# frozen_string_literal: true

module Vert
  module Concerns
    module MultiTenant
      extend ActiveSupport::Concern

      included do
        validates :tenant_id, presence: true, if: :require_tenant_id?
        default_scope do
          if Vert::Current.tenant_id.present?
            where(tenant_id: Vert::Current.tenant_id)
          else
            all
          end
        end
        before_validation :set_tenant_id, on: :create
      end

      class_methods do
        def unscoped_for_tenant(tenant_id)
          unscoped.where(tenant_id: tenant_id)
        end

        def all_tenants
          unscoped
        end

        def belongs_to_current_tenant?(id)
          exists?(id: id)
        end
      end

      private

      def require_tenant_id?
        true
      end

      def set_tenant_id
        self.tenant_id ||= Vert::Current.tenant_id
      end
    end
  end
end
