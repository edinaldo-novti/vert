# frozen_string_literal: true

module Vert
  module Concerns
    module UuidPrimaryKey
      extend ActiveSupport::Concern

      included do
        before_create :set_uuid
      end

      private

      def set_uuid
        return unless has_attribute?(:id)
        return if id.present?
        self.id = generate_uuid_v7
      end

      def generate_uuid_v7
        if SecureRandom.respond_to?(:uuid_v7)
          SecureRandom.uuid_v7
        else
          generate_uuid_v7_fallback
        end
      end

      def generate_uuid_v7_fallback
        timestamp_ms = (Time.now.to_f * 1000).to_i
        random_bytes = SecureRandom.random_bytes(10)
        bytes = [
          (timestamp_ms >> 40) & 0xFF, (timestamp_ms >> 32) & 0xFF, (timestamp_ms >> 24) & 0xFF,
          (timestamp_ms >> 16) & 0xFF, (timestamp_ms >> 8) & 0xFF, timestamp_ms & 0xFF,
          (0x70 | (random_bytes[0] & 0x0F)), random_bytes[1], (0x80 | (random_bytes[2] & 0x3F)),
          random_bytes[3], random_bytes[4], random_bytes[5], random_bytes[6], random_bytes[7], random_bytes[8], random_bytes[9]
        ].pack("C*")
        hex = bytes.unpack1("H*")
        "#{hex[0..7]}-#{hex[8..11]}-#{hex[12..15]}-#{hex[16..19]}-#{hex[20..31]}"
      end
    end
  end
end
