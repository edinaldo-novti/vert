# frozen_string_literal: true

module Vert
  module Concerns
    # CurrentAttributes - Thread-safe request context
    class Current < ActiveSupport::CurrentAttributes
      attribute :tenant_id, :company_id, :user_id, :request_id, :rls_configured

      def self.reset_all
        reset
      end

      def self.set_context(tenant_id:, user_id: nil, company_id: nil, request_id: nil)
        self.tenant_id = tenant_id
        self.user_id = user_id
        self.company_id = company_id
        self.request_id = request_id || SecureRandom.uuid
      end

      def self.serialize
        { tenant_id: tenant_id, user_id: user_id, company_id: company_id, request_id: request_id }
      end

      def self.deserialize(hash)
        return unless hash.is_a?(Hash)
        set_context(
          tenant_id: hash[:tenant_id] || hash["tenant_id"],
          user_id: hash[:user_id] || hash["user_id"],
          company_id: hash[:company_id] || hash["company_id"],
          request_id: hash[:request_id] || hash["request_id"]
        )
      end

      def self.tenant_set?
        tenant_id.present?
      end

      def self.company_set?
        company_id.present?
      end

      def self.require_tenant!
        raise Vert::TenantNotSetError, "Tenant context not set" unless tenant_set?
      end

      def self.require_company!
        raise Vert::CompanyNotSetError, "Company context not set" unless company_set?
      end
    end
  end

  Current = Concerns::Current
end
