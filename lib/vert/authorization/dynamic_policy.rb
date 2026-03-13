# frozen_string_literal: true

module Vert
  module Authorization
    class DynamicPolicy
      attr_reader :user, :record, :context

      def initialize(user, record, context = {})
        @user = user
        @record = record
        @context = default_context.merge(context)
      end

      def index?
        has_permission?("#{resource_name}.list")
      end

      def show?
        has_permission?("#{resource_name}.read")
      end

      def create?
        has_permission?("#{resource_name}.create")
      end

      def new?
        create?
      end

      def update?
        has_permission?("#{resource_name}.update")
      end

      def edit?
        update?
      end

      def destroy?
        has_permission?("#{resource_name}.delete")
      end

      def export?
        has_permission?("#{resource_name}.export")
      end

      def import?
        has_permission?("#{resource_name}.import")
      end

      def approve?
        has_permission?("#{resource_name}.approve")
      end

      def reject?
        has_permission?("#{resource_name}.reject")
      end

      def cancel?
        has_permission?("#{resource_name}.cancel")
      end

      def print?
        has_permission?("#{resource_name}.print")
      end

      class Scope
        attr_reader :user, :scope, :context

        def initialize(user, scope, context = {})
          @user = user
          @scope = scope
          @context = context
        end

        def resolve
          if PermissionResolver.has_permission?(user, "#{resource_name}.list", context)
            own_records_only? ? scope.where(created_by: user.id) : scope.all
          else
            scope.none
          end
        end

        private

        def resource_name
          scope.model_name.plural
        end

        def own_records_only?
          PermissionResolver.get_condition(user, "#{resource_name}.list", "own_records_only", context) == true
        end
      end

      protected

      def has_permission?(permission_code)
        return true if user_super_admin?
        PermissionResolver.has_permission?(user, permission_code, context)
      end

      def permission_condition(condition_key)
        PermissionResolver.get_condition(user, "#{resource_name}.#{current_action}", condition_key, context)
      end

      def allowed_fields
        PermissionResolver.get_allowed_fields(user, "#{resource_name}.read", context)
      end

      def denied_fields
        PermissionResolver.get_denied_fields(user, "#{resource_name}.read", context)
      end

      def can_see_field?(field_name)
        field = field_name.to_s
        denied = denied_fields
        return false if denied.include?(field)
        allowed = allowed_fields
        return true if allowed.nil?
        allowed.include?(field)
      end

      def resource_name
        @resource_name ||= begin
          klass = record.is_a?(Class) ? record : record.class
          klass.model_name.plural
        end
      end

      def service_name
        @service_name ||= resource_name.split("/").first
      end

      private

      def default_context
        {
          tenant_id: Vert::Current.tenant_id,
          company_id: Vert::Current.company_id,
          user_id: user&.id
        }
      end

      def current_action
        context[:action] || caller_action
      end

      def caller_action
        caller_locations(2, 1).first&.label&.delete_suffix("?")
      end

      def user_super_admin?
        user.respond_to?(:super_admin?) && user.super_admin?
      end
    end
  end
end
