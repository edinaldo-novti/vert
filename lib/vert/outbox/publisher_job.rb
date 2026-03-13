# frozen_string_literal: true

module Vert
  module Outbox
    class PublisherJob
      include Sidekiq::Job if defined?(Sidekiq::Job)
      sidekiq_options queue: :critical, retry: 3 if respond_to?(:sidekiq_options)

      def perform
        return unless Vert.config.enable_outbox
        return unless outbox_event_class

        outbox_event_class.pending_events.find_each { |event| publish_event(event) }
        outbox_event_class.failed_events.find_each { |event| publish_event(event) }
      end

      private

      def publish_event(event)
        Publisher.with_connection { |publisher| publisher.publish(event) }
      rescue StandardError => e
        Rails.logger.error("[Vert::Outbox] Failed #{event.event_type}: #{e.message}") if defined?(Rails)
      end

      def outbox_event_class
        @outbox_event_class ||= (Object.const_get("OutboxEvent") rescue nil)
      end
    end
  end
end
