# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "base64"

module Vert
  module Clients
    class DocumentServiceClient
      attr_reader :base_url, :timeout

      def initialize(base_url: nil, timeout: 30)
        @base_url = base_url || Vert.config.document_service_url
        @timeout = timeout
      end

      def upload(resource:, filename:, content:, content_type:, metadata: {})
        uri = URI.parse("#{base_url}/api/v1/objects")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        add_auth_headers(request)
        request.body = {
          object: {
            resource: resource,
            original_filename: filename,
            content_type: content_type,
            content_base64: Base64.strict_encode64(content.to_s),
            metadata: metadata
          }
        }.to_json
        execute_request(uri, request)
      end

      def download_url(object_id:, disposition: "inline", expires_in: 3600)
        uri = URI.parse("#{base_url}/api/v1/objects/#{object_id}/download_url")
        uri.query = URI.encode_www_form(disposition: disposition, expires_in: expires_in)
        request = Net::HTTP::Get.new(uri)
        add_auth_headers(request)
        execute_request(uri, request)
      end

      def download(object_id:)
        result = download_url(object_id: object_id)
        return nil unless result[:success]
        url = result[:data][:url]
        response = Net::HTTP.get_response(URI.parse(url))
        response.body if response.is_a?(Net::HTTPSuccess)
      end

      def object(object_id)
        uri = URI.parse("#{base_url}/api/v1/objects/#{object_id}")
        request = Net::HTTP::Get.new(uri)
        add_auth_headers(request)
        execute_request(uri, request)
      end

      def delete_object(object_id)
        uri = URI.parse("#{base_url}/api/v1/objects/#{object_id}")
        request = Net::HTTP::Delete.new(uri)
        add_auth_headers(request)
        execute_request(uri, request)
      end

      def list_objects(resource: nil, page: 1, per_page: 20)
        uri = URI.parse("#{base_url}/api/v1/objects")
        params = { page: page, per_page: per_page }
        params[:resource] = resource if resource
        uri.query = URI.encode_www_form(params)
        request = Net::HTTP::Get.new(uri)
        add_auth_headers(request)
        execute_request(uri, request)
      end

      private

      def execute_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        response = http.request(request)
        case response
        when Net::HTTPSuccess
          body = JSON.parse(response.body, symbolize_names: true)
          { success: true, data: body[:data] || body }
        else
          body = (JSON.parse(response.body, symbolize_names: true) rescue {})
          { success: false, error: body[:error] || response.message, status: response.code.to_i }
        end
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def add_auth_headers(request)
        request["Accept"] = "application/json"
        request["X-Tenant-ID"] = Vert::Current.tenant_id.to_s if Vert::Current.tenant_id
        request["X-Company-ID"] = Vert::Current.company_id.to_s if Vert::Current.company_id
        request["X-User-ID"] = Vert::Current.user_id.to_s if Vert::Current.user_id
        request["X-Request-ID"] = Vert::Current.request_id.to_s if Vert::Current.request_id
      end
    end
  end
end
