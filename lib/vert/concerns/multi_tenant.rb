# frozen_string_literal: true

module Vert
  module Concerns
    # MultiTenant
    # -----------
    # Adiciona escopo automático por `tenant_id` baseado em `Vert::Current.tenant_id`.
    #
    # ## Uso básico
    #   class Order < ApplicationRecord
    #     include Vert::Concerns::MultiTenant
    #   end
    #
    # ## System records (tenant_id NULL)
    #
    # Alguns modelos têm registros "globais" que devem ser visíveis em todos
    # os tenants — ex: `Role` system, `Plan`, `Permission` catálogo. Esses
    # registros são identificados por `tenant_id IS NULL`.
    #
    # Por default, o `default_scope` filtra `where(tenant_id = current)`, o que
    # exclui esses registros silenciosamente quando há tenant ativo. Para
    # incluí-los, use o opt-in:
    #
    #   class Role < ApplicationRecord
    #     include Vert::Concerns::MultiTenant
    #     multi_tenant_options include_system_records: true
    #   end
    #
    # Com essa opção, o default_scope passa a ser:
    #   where("tenant_id = ? OR tenant_id IS NULL", Vert::Current.tenant_id)
    #
    # Aplica-se também à validação: `tenant_id` deixa de ser obrigatório.
    #
    # ## Bypass manual
    #
    # Para queries específicas que precisam ignorar o escopo:
    #
    #   Order.unscoped.where(id: external_id)
    #   Order.unscoped_for_tenant(other_tenant_id).find(id)
    module MultiTenant
      extend ActiveSupport::Concern

      class_methods do
        # Configura comportamento do MultiTenant. Aceita:
        #   - include_system_records: true  → default_scope inclui tenant_id NULL
        def multi_tenant_options(include_system_records: false)
          @multi_tenant_include_system_records = include_system_records
        end

        def multi_tenant_include_system_records?
          @multi_tenant_include_system_records == true
        end

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

      included do
        validates :tenant_id, presence: true, if: :require_tenant_id?

        default_scope do
          current_tenant = Vert::Current.tenant_id
          if current_tenant.present?
            if multi_tenant_include_system_records?
              where("#{table_name}.tenant_id = ? OR #{table_name}.tenant_id IS NULL", current_tenant)
            else
              where(tenant_id: current_tenant)
            end
          else
            all
          end
        end

        before_validation :set_tenant_id, on: :create
      end

      private

      def require_tenant_id?
        return false if self.class.multi_tenant_include_system_records?

        true
      end

      def set_tenant_id
        self.tenant_id ||= Vert::Current.tenant_id
      end
    end
  end
end
