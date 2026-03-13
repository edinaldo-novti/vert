# frozen_string_literal: true

require "bunny"

module Vert
  module Outbox
    class Publisher
      attr_reader :connection, :channel, :exchange

      def initialize
        @connection = nil
        @channel = nil
        @exchange = nil
      end

      def connect
        @connection = Bunny.new(Vert.config.rabbitmq_url)
        @connection.start
        @channel = @connection.create_channel
        @exchange = @channel.topic(Vert.config.exchange_name, durable: true)
        self
      end

      def close
        @connection&.close
        @connection = nil
        @channel = nil
        @exchange = nil
      end

      def connected?
        @connection&.open? && @channel&.open?
      end

      def publish(event)
        connect unless connected?
        message = build_message(event)
        @exchange.publish(
          message.to_json,
          routing_key: event.routing_key,
          persistent: true,
          content_type: "application/json",
          message_id: event.id.to_s,
          timestamp: event.created_at.to_i,
          headers: event.message_headers
        )
        event.mark_as_published!
        true
      rescue StandardError => e
        event.mark_as_failed!(e)
        false
      end

      def publish_batch(events)
        results = { published: 0, failed: 0 }
        events.each { |event| publish(event) ? results[:published] += 1 : results[:failed] += 1 }
        results
      end

      class << self
        def with_connection
          publisher = new
          publisher.connect
          yield publisher
        ensure
          publisher&.close
        end

        def publish_pending(batch_size: 100)
          return { published: 0, failed: 0, error: "OutboxEvent not defined" } unless outbox_event_class
          results = { published: 0, failed: 0 }
          with_connection do |publisher|
            outbox_event_class.publishable.find_in_batches(batch_size: batch_size) do |events|
              batch_results = publisher.publish_batch(events)
              results[:published] += batch_results[:published]
              results[:failed] += batch_results[:failed]
            end
          end
          results
        end

        private

        def outbox_event_class
          @outbox_event_class ||= (Object.const_get("OutboxEvent") rescue nil)
        end
      end

      private

      def build_message(event)
        {
          event_id: event.id.to_s,
          event_type: event.event_type,
          aggregate_type: event.aggregate_type,
          aggregate_id: event.aggregate_id.to_s,
          tenant_id: event.tenant_id.to_s,
          occurred_at: event.created_at.iso8601,
          metadata: { tenant_id: event.tenant_id.to_s, published_at: Time.current.iso8601 },
          data: event.payload.is_a?(Hash) ? (event.payload[:data] || event.payload["data"] || event.payload) : event.payload
        }
      end
    end
  end
end
