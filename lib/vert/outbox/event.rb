# frozen_string_literal: true

module Vert
  module Outbox
    module Event
      extend ActiveSupport::Concern

      included do
        validates :event_type, presence: true
        validates :aggregate_type, presence: true
        validates :aggregate_id, presence: true
        validates :payload, presence: true
        validates :status, presence: true
        enum :status, { pending: 0, published: 1, failed: 2 }, prefix: true
        scope :pending_events, -> { status_pending.order(:created_at) }
        scope :failed_events, -> { status_failed.where("retry_count < ?", max_retry_count).order(:created_at) }
        scope :by_aggregate, ->(type, id) { where(aggregate_type: type, aggregate_id: id) }
        scope :publishable, -> { pending_events.or(failed_events) }
      end

      class_methods do
        def max_retry_count
          5
        end

        def create_event(event_type:, aggregate_type:, aggregate_id:, payload:)
          create!(
            tenant_id: Vert::Current.tenant_id,
            event_type: event_type,
            aggregate_type: aggregate_type,
            aggregate_id: aggregate_id,
            payload: payload,
            status: :pending
          )
        end

        def publish_for(aggregate, event_type:, payload: {})
          create_event(
            event_type: event_type,
            aggregate_type: aggregate.class.name,
            aggregate_id: aggregate.id,
            payload: payload.merge(id: aggregate.id, tenant_id: aggregate.tenant_id)
          )
        end
      end

      def mark_as_published!
        update!(status: :published, published_at: Time.current)
      end

      def mark_as_failed!(error)
        update!(status: :failed, retry_count: retry_count + 1, last_error: error.to_s, failed_at: Time.current)
      end

      def can_retry?
        status_failed? && retry_count < self.class.max_retry_count
      end

      def routing_key
        event_type.tr("_", ".")
      end

      def message_headers
        { tenant_id: tenant_id, event_type: event_type, aggregate_type: aggregate_type, aggregate_id: aggregate_id, event_id: id, timestamp: created_at.iso8601 }
      end
    end
  end
end
