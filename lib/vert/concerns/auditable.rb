# frozen_string_literal: true

module Vert
  module Concerns
    module Auditable
      extend ActiveSupport::Concern

      included do
        before_create :set_created_by
        before_update :set_updated_by
      end

      private

      def set_created_by
        self.created_by ||= Vert::Current.user_id if has_attribute?(:created_by)
      end

      def set_updated_by
        self.updated_by = Vert::Current.user_id if has_attribute?(:updated_by)
      end
    end
  end
end
