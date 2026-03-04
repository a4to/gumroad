# frozen_string_literal: true

require "httparty"

module Gr
  class ApiClient
    include HTTParty

    def initialize(host:, token:, default_api_prefix: "/v2")
      @host = host.chomp("/")
      @token = token
      @default_api_prefix = default_api_prefix.sub(%r{/\z}, "")
    end

    def request(method:, endpoint:, fields: {}, headers: {})
      url = resolved_url(endpoint)
      query = @token.nil? || @token.empty? ? {} : { access_token: @token }
      request_headers = headers.dup
      request_options = { query:, headers: request_headers }

      if %w[GET DELETE].include?(method)
        request_options[:query] = query.merge(fields)
      elsif fields.any?
        request_options[:body] = fields
      end

      self.class.public_send(method.downcase, url, request_options)
    end

    private
      def resolved_url(endpoint)
        return endpoint if endpoint.start_with?("http://", "https://")

        normalized_endpoint = endpoint.sub(%r{\A/+}, "")
        if normalized_endpoint.start_with?("v2/")
          "#{@host}/#{normalized_endpoint}"
        else
          "#{@host}#{@default_api_prefix}/#{normalized_endpoint}"
        end
      end
  end
end
