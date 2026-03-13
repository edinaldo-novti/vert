# frozen_string_literal: true

module Vert
  module Concerns
    module CompanyScoped
      extend ActiveSupport::Concern

      included do
        validates :company_id, presence: true
        validate :company_belongs_to_tenant, if: -> { tenant_id.present? && company_id.present? }
        default_scope do
          if Vert::Current.company_id.present?
            where(company_id: Vert::Current.company_id)
          else
            all
          end
        end
        before_validation :set_company_id, on: :create
      end

      class_methods do
        def for_company(company_id)
          unscope(where: :company_id).where(company_id: company_id)
        end

        def all_companies
          unscope(where: :company_id)
        end

        def belongs_to_current_company?(id)
          exists?(id: id)
        end
      end

      private

      def set_company_id
        self.company_id ||= Vert::Current.company_id
      end

      def company_belongs_to_tenant
        return unless defined?(Company)
        return if Company.unscoped.exists?(id: company_id, tenant_id: tenant_id)
        errors.add(:company_id, "does not belong to the current tenant")
      end
    end
  end
end
