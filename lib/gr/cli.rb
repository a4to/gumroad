# frozen_string_literal: true

require "json"
require "optparse"
require_relative "api_client"

module Gr
  class CLI
    DEFAULT_API_HOST = "https://api.gumroad.com"
    ACCESS_TOKEN_ENV = "GUMROAD_ACCESS_TOKEN"
    ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE].freeze

    def initialize(stdout: $stdout, stderr: $stderr, env: ENV)
      @stdout = stdout
      @stderr = stderr
      @env = env
    end

    def run(argv)
      command = argv.shift
      return print_help if command.nil? || %w[-h --help help].include?(command)

      case command
      when "api"
        run_api(argv)
      else
        @stderr.puts "Unknown command: #{command}"
        @stderr.puts "Run `gr --help` for usage."
        1
      end
    end

    private
      def run_api(argv)
        options = {
          method: "GET",
          fields: [],
          headers: [],
          raw: false,
          host: DEFAULT_API_HOST,
          token: @env[ACCESS_TOKEN_ENV]
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: gr api <endpoint> [options]"
          opts.on("-X", "--method METHOD", "HTTP method (default: GET)") { |value| options[:method] = value.upcase }
          opts.on("-f", "--field KEY=VALUE", "Add request field (can be repeated)") { |value| options[:fields] << value }
          opts.on("-H", "--header KEY:VALUE", "Add request header (can be repeated)") { |value| options[:headers] << value }
          opts.on("--host HOST", "API host (default: #{DEFAULT_API_HOST})") { |value| options[:host] = value }
          opts.on("--token TOKEN", "API access token (or #{ACCESS_TOKEN_ENV})") { |value| options[:token] = value }
          opts.on("--raw", "Print response body without JSON formatting") { options[:raw] = true }
          opts.on("-h", "--help", "Show help for `gr api`") do
            @stdout.puts opts
            return 0
          end
        end

        endpoint = parser.parse(argv).first
        if endpoint.nil?
          @stderr.puts "Missing endpoint."
          @stderr.puts parser
          return 1
        end

        fields = parse_key_value_pairs(values: options[:fields], separator: "=")
        return 1 if fields.nil?

        headers = parse_key_value_pairs(values: options[:headers], separator: ":")
        return 1 if headers.nil?

        unless ALLOWED_METHODS.include?(options[:method])
          @stderr.puts "Invalid HTTP method: #{options[:method]}"
          @stderr.puts "Allowed methods: #{ALLOWED_METHODS.join(', ')}"
          return 1
        end

        response = begin
          Gr::ApiClient.new(host: options[:host], token: options[:token]).request(
            method: options[:method],
            endpoint:,
            fields:,
            headers:
          )
        rescue StandardError => e
          @stderr.puts "Request failed: #{e.class} - #{e.message}"
          return 1
        end

        print_response(response:, raw: options[:raw])
      end

      def parse_key_value_pairs(values:, separator:)
        pairs = {}
        values.each do |value|
          key, parsed_value = value.split(separator, 2)
          if key.nil? || key.empty? || parsed_value.nil?
            @stderr.puts "Invalid key/value pair: #{value.inspect}"
            return nil
          end

          pairs[key] = parsed_value
        end
        pairs
      end

      def print_response(response:, raw:)
        body = response.body.to_s
        parsed_body = parse_json(body)

        if raw
          @stdout.puts body
        elsif parsed_body.nil?
          @stdout.puts body
        else
          @stdout.puts JSON.pretty_generate(parsed_body)
        end

        response_ok = response.code.between?(200, 299)
        api_ok = !parsed_body.is_a?(Hash) || parsed_body.fetch("success", true)
        if response_ok && api_ok
          0
        else
          @stderr.puts "Request failed (HTTP #{response.code})."
          1
        end
      end

      def parse_json(body)
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def print_help
        @stdout.puts <<~HELP
          Usage:
            gr api <endpoint> [options]

          Examples:
            gr api user
            gr api sales -f after=2026-03-01
            gr api sales/ABCD1234 -X PUT -f tracking_url=https://example.com/track

          Global token:
            Set #{ACCESS_TOKEN_ENV} or pass --token.
        HELP
        0
      end
  end
end
