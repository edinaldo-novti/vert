# frozen_string_literal: true

module Vert
  module Authorization
    module ControllerMethods
      extend ActiveSupport::Concern

      included do
        rescue_from Pundit::NotAuthorizedError, with: :render_forbidden if defined?(Pundit)
      end

      def authorize_with_context(record, query = nil, context = {})
        return record unless Vert.config.enable_authorization && defined?(Pundit)
        query ||= "#{action_name}?"
        policy_context = authorization_context.merge(context)
        policy = policy_with_context(record, policy_context)
        unless policy.public_send(query)
          raise Pundit::NotAuthorizedError, query: query, record: record, policy: policy
        end
        record
      end

      def policy_with_context(record, context = {})
        policy_class = PolicyFinder.new(record).policy
        policy_class.new(current_user, record, context)
      end

      def has_permission?(permission_code, context = {})
        return false unless Vert.config.enable_authorization
        PermissionResolver.has_permission?(current_user, permission_code, authorization_context.merge(context))
      end

      def can_see_field?(resource, field)
        allowed = PermissionResolver.get_allowed_fields(current_user, "#{resource}.read", authorization_context)
        denied = PermissionResolver.get_denied_fields(current_user, "#{resource}.read", authorization_context)
        return false if denied.include?(field.to_s)
        return true if allowed.nil?
        allowed.include?(field.to_s)
      end

      def allowed_fields_for(resource)
        PermissionResolver.get_allowed_fields(current_user, "#{resource}.read", authorization_context)
      end

      def denied_fields_for(resource)
        PermissionResolver.get_denied_fields(current_user, "#{resource}.read", authorization_context)
      end

      def current_user_permissions
        PermissionResolver.user_permissions(current_user, authorization_context)
      end

      protected

      def authorization_context
        {
          tenant_id: current_tenant_id,
          company_id: current_company_id,
          user_id: current_user&.id,
          action: action_name
        }
      end

      def current_tenant_id
        Vert::Current.tenant_id
      end

      def current_company_id
        Vert::Current.company_id
      end

      private

      def render_forbidden(exception)
        render json: {
          error: "Access denied",
          message: "You do not have permission to perform this action",
          permission: exception.query&.to_s&.delete_suffix("?"),
          resource: exception.record.is_a?(Class) ? exception.record.name : exception.record.class.name
        }, status: :forbidden
      end
    end
  end
end
