# frozen_string_literal: true

module Vert
  module Authorization
    class PolicyFinder
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def policy
        find_policy || DynamicPolicy
      end

      def policy!
        policy || raise(Pundit::NotDefinedError, "Unable to find policy for #{object}")
      end

      def scope
        find_scope || DynamicPolicy::Scope
      end

      def scope!
        scope || raise(Pundit::NotDefinedError, "Unable to find scope for #{object}")
      end

      private

      def find_policy
        specific_policy = "#{model_name}Policy"
        return Object.const_get(specific_policy) if Object.const_defined?(specific_policy)

        namespaced_policy = "#{model_namespace}::#{model_class_name}Policy"
        return Object.const_get(namespaced_policy) if Object.const_defined?(namespaced_policy)

        service_policy = "#{service_name}::DynamicPolicy"
        return Object.const_get(service_policy) if Object.const_defined?(service_policy)

        nil
      rescue NameError
        nil
      end

      def find_scope
        policy_class = find_policy
        return nil unless policy_class
        policy_class.const_defined?(:Scope) ? policy_class::Scope : nil
      end

      def model_name
        case object
        when Class then object.name
        when Symbol, String then object.to_s.camelize
        else object.class.name
        end
      end

      def model_class_name
        model_name.demodulize
      end

      def model_namespace
        model_name.deconstantize.presence || "App"
      end

      def service_name
        model_namespace.underscore.split("/").first.camelize
      end
    end
  end
end
