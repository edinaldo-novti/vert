# frozen_string_literal: true

require "discard"

module Vert
  module Concerns
    module SoftDeletable
      extend ActiveSupport::Concern

      included do
        include ::Discard::Model
        default_scope -> { kept }
      end

      class_methods do
        def deleted
          discarded
        end

        def active
          kept
        end

        def with_deleted
          with_discarded
        end

        def only_deleted
          discarded
        end
      end

      def soft_delete
        discard
      end

      def restore
        undiscard
      end

      def deleted?
        discarded?
      end
    end
  end
end
