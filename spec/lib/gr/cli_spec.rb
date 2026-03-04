# frozen_string_literal: true

require "spec_helper"
require Rails.root.join("lib/gr/cli")

describe Gr::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:env) { {} }
  let(:cli) { described_class.new(stdout:, stderr:, env:) }

  describe "#run" do
    context "when command is unknown" do
      it "returns non-zero" do
        expect(cli.run(["unknown"])).to eq(1)
        expect(stderr.string).to include("Unknown command")
      end
    end

    context "with api command" do
      it "calls v2 endpoint and prints formatted JSON" do
        stub_request(:get, "https://api.gumroad.com/v2/user")
          .with(query: { access_token: "token-1" })
          .to_return(status: 200, body: { success: true, user: { name: "Seller" } }.to_json)

        expect(cli.run(["api", "user", "--token", "token-1"])).to eq(0)
        expect(stdout.string).to include("\"user\"")
        expect(stderr.string).to eq("")
      end

      it "sends fields as query params for GET requests" do
        stub_request(:get, "https://api.gumroad.com/v2/sales")
          .with(query: { access_token: "token-2", after: "2026-03-01", email: "buyer@example.com" })
          .to_return(status: 200, body: { success: true, sales: [] }.to_json)

        exit_code = cli.run(["api", "sales", "--token", "token-2", "-f", "after=2026-03-01", "-f", "email=buyer@example.com"])
        expect(exit_code).to eq(0)
      end

      it "sends fields in request body for mutating requests" do
        stub_request(:put, "https://api.gumroad.com/v2/sales/SALE_1")
          .with(query: { access_token: "token-3" }, body: { tracking_url: "https://carrier.example/track" })
          .to_return(status: 200, body: { success: true, sale: { id: "SALE_1" } }.to_json)

        exit_code = cli.run(["api", "sales/SALE_1", "--token", "token-3", "-X", "PUT", "-f", "tracking_url=https://carrier.example/track"])
        expect(exit_code).to eq(0)
      end

      it "returns non-zero when API success is false" do
        stub_request(:get, "https://api.gumroad.com/v2/user")
          .with(query: { access_token: "token-4" })
          .to_return(status: 200, body: { success: false, message: "Not authorized" }.to_json)

        expect(cli.run(["api", "user", "--token", "token-4"])).to eq(1)
        expect(stderr.string).to include("Request failed")
      end

      it "returns non-zero for invalid fields" do
        expect(cli.run(["api", "sales", "-f", "invalid"])).to eq(1)
        expect(stderr.string).to include("Invalid key/value pair")
      end

      it "returns non-zero for invalid HTTP method" do
        expect(cli.run(["api", "user", "-X", "TRACE"])).to eq(1)
        expect(stderr.string).to include("Invalid HTTP method")
      end
    end
  end
end
