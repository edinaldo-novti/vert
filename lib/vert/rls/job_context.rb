# frozen_string_literal: true

module Vert
  module Rls
    module JobContext
      extend ActiveSupport::Concern

      class_methods do
        def perform_async(*args)
          super(*args, __vert_context__: Vert::Current.serialize)
        end

        def perform_in(interval, *args)
          super(interval, *args, __vert_context__: Vert::Current.serialize)
        end

        def perform_at(timestamp, *args)
          super(timestamp, *args, __vert_context__: Vert::Current.serialize)
        end
      end

      def perform(*args)
        context = args.last.is_a?(Hash) && (args.last.delete(:__vert_context__) || args.last.delete("__vert_context__"))
        Vert::Current.deserialize(context) if context
        Vert::Rls::ConnectionHandler.set_context(tenant_id: Vert::Current.tenant_id, company_id: Vert::Current.company_id, user_id: Vert::Current.user_id) if Vert.config.enable_rls && Vert::Current.tenant_id.present?

        clean = args.last.is_a?(Hash) ? (args[0..-2] + [args.last.except(:__vert_context__, "__vert_context__")]).reject { |a| a.respond_to?(:empty?) && a.empty? } : args
        super(*clean)
      ensure
        Vert::Current.reset_all
        Vert::Rls::ConnectionHandler.reset_context if Vert.config.enable_rls
      end
    end

    class JobMiddleware
      def call(_worker, job, _queue)
        context = job.delete("__vert_context__")
        if context
          Vert::Current.deserialize(context)
          Vert::Rls::ConnectionHandler.set_context(tenant_id: Vert::Current.tenant_id, company_id: Vert::Current.company_id, user_id: Vert::Current.user_id) if Vert.config.enable_rls && Vert::Current.tenant_id.present?
        end
        yield
      ensure
        Vert::Current.reset_all
        Vert::Rls::ConnectionHandler.reset_context if Vert.config.enable_rls
      end
    end

    class JobClientMiddleware
      def call(_worker_class, job, _queue, _redis_pool)
        job["__vert_context__"] = Vert::Current.serialize
        yield
      end
    end
  end
end
