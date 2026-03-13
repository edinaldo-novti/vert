# frozen_string_literal: true

module Vert
  module Concerns
    module DocumentStoreable
      extend ActiveSupport::Concern

      included do
        class_attribute :document_attachments, default: {}
      end

      class_methods do
        def has_document(name, resource:, content_type: nil)
          document_attachments[name] = { resource: resource, content_type: content_type }

          define_method(name) do
            object_id = send("#{name}_object_id")
            return nil unless object_id.present?
            @document_cache ||= {}
            @document_cache[name] ||= Vert::Concerns::DocumentStoreable::DocumentAttachment.new(
              object_id: object_id,
              resource: document_attachments[name][:resource],
              owner: self
            )
          end

          define_method("#{name}=") do |value|
            return if value.nil?
            result = attach_document(name, value)
            if result[:success]
              send("#{name}_object_id=", result[:data][:id])
              @document_cache&.delete(name)
            else
              errors.add(name, "upload failed: #{result[:error]}")
            end
          end

          define_method("attach_#{name}") do |content:, filename:, content_type: nil|
            config = self.class.document_attachments[name]
            ct = content_type || config[:content_type] || detect_content_type(filename)
            result = document_service_client.upload(
              resource: config[:resource],
              filename: filename,
              content: content,
              content_type: ct,
              metadata: document_metadata(name)
            )
            if result[:success]
              send("#{name}_object_id=", result[:data][:id])
              @document_cache&.delete(name)
            else
              errors.add(name, "upload failed: #{result[:error]}")
            end
            result
          end

          define_method("#{name}_attached?") { send("#{name}_object_id").present? }

          define_method("purge_#{name}") do
            object_id = send("#{name}_object_id")
            return true unless object_id.present?
            result = document_service_client.delete_object(object_id)
            if result[:success]
              send("#{name}_object_id=", nil)
              @document_cache&.delete(name)
              true
            else
              false
            end
          end
        end
      end

      private

      def document_service_client
        @document_service_client ||= Vert::Clients::DocumentServiceClient.new
      end

      def attach_document(name, value)
        config = self.class.document_attachments[name]
        case value
        when ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile
          document_service_client.upload(
            resource: config[:resource],
            filename: value.original_filename,
            content: value.read,
            content_type: value.content_type || config[:content_type],
            metadata: document_metadata(name)
          )
        when Hash
          document_service_client.upload(
            resource: config[:resource],
            filename: value[:filename],
            content: value[:content],
            content_type: value[:content_type] || config[:content_type],
            metadata: document_metadata(name)
          )
        when String
          document_service_client.upload(
            resource: config[:resource],
            filename: "#{name}_#{id || SecureRandom.uuid}.bin",
            content: value,
            content_type: config[:content_type] || "application/octet-stream",
            metadata: document_metadata(name)
          )
        else
          { success: false, error: "Invalid value type for document" }
        end
      end

      def document_metadata(name)
        metadata = { owner_type: self.class.name, owner_id: id, field_name: name.to_s }
        metadata[:tenant_id] = tenant_id if respond_to?(:tenant_id)
        metadata[:company_id] = company_id if respond_to?(:company_id)
        metadata
      end

      def detect_content_type(filename)
        ext = File.extname(filename).downcase
        CONTENT_TYPES[ext] || "application/octet-stream"
      end

      CONTENT_TYPES = {
        ".xml" => "application/xml", ".pdf" => "application/pdf",
        ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".gif" => "image/gif",
        ".csv" => "text/csv", ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".xls" => "application/vnd.ms-excel", ".doc" => "application/msword",
        ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".zip" => "application/zip", ".txt" => "text/plain", ".json" => "application/json"
      }.freeze
    end

    class DocumentStoreable::DocumentAttachment
      attr_reader :storage_object_id, :resource, :owner

      def initialize(object_id:, resource:, owner:)
        @storage_object_id = object_id
        @resource = resource
        @owner = owner
      end

      def url(disposition: "inline", expires_in: 3600)
        result = client.download_url(object_id: storage_object_id, disposition: disposition, expires_in: expires_in)
        result[:success] ? result[:data][:url] : nil
      end

      def download
        client.download(object_id: storage_object_id)
      end

      def details
        result = client.object(storage_object_id)
        result[:success] ? result[:data] : nil
      end

      def filename
        details&.dig(:original_filename)
      end

      def content_type
        details&.dig(:mime_type)
      end

      def byte_size
        details&.dig(:size)
      end

      def attached?
        storage_object_id.present?
      end

      private

      def client
        @client ||= Vert::Clients::DocumentServiceClient.new
      end
    end
  end
end
