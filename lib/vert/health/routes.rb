# frozen_string_literal: true

module Vert
  module Health
    module Routes
      class << self
        def mount(router, path: nil)
          path ||= Vert.config.health_check_path
          router.instance_eval do
            scope path do
              get "/", to: "health#show", as: :health
              get "/live", to: "health#live", as: :health_live
              get "/ready", to: "health#ready", as: :health_ready
            end
          end
        end
      end
    end

    module ControllerMixin
      extend ActiveSupport::Concern

      def show
        result = Vert::Health.check_all
        status = result[:status] == "healthy" ? :ok : :service_unavailable
        render json: result, status: status
      end

      def live
        render json: Vert::Health.liveness, status: :ok
      end

      def ready
        result = Vert::Health.readiness
        status = result[:status] == "ready" ? :ok : :service_unavailable
        render json: result, status: status
      end
    end

    class Controller < ActionController::API
      include ControllerMixin
    end
  end
end if defined?(ActionController::API)
