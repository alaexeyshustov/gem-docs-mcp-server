# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::MCP::Server do
  class CapturingTransport
    attr_reader :messages

    def initialize
      @messages = []
    end

    def send_message(message)
      @messages << message
    end
  end

  describe ".build_fast_mcp_server" do
    it "registers the supported gem-docs MCP tools" do
      server = described_class.build_fast_mcp_server

      expect(server.tools.keys).to contain_exactly("list", "summary", "classes", "lookup", "search")
    end

    it "delegates tool calls to the shared CLI command layer" do
      stub_const("GemDocs::Commands::List", Class.new(GemDocs::Commands::Base) do
        def call(format: "text", **)
          out.puts(%([{\"name\":\"rack\",\"version\":\"3.2.6\",\"doc_source\":\"yard\"}]))
          format == "json" ? 0 : 1
        end
      end)
      GemDocs::MCP::Tools::List.command(GemDocs::Commands::List) if defined?(GemDocs::MCP::Tools::List)

      server = described_class.build_fast_mcp_server
      transport = CapturingTransport.new
      server.transport = transport

      server.handle_json_request(
        {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: {
            name: "list",
            arguments: {}
          }
        }
      )
      response = transport.messages.last

      expect(response.dig(:result, :isError)).to be(false)
      expect(response.dig(:result, :content, 0, :text)).to eq("[{\"name\":\"rack\",\"version\":\"3.2.6\",\"doc_source\":\"yard\"}]\n")
    end

    it "returns the shared CLI JSON error envelope when a delegated command fails" do
      stub_const("GemDocs::Commands::Summary", Class.new(GemDocs::Commands::Base) do
        def call(**)
          raise GemDocs::GemNotFound.new("missing-gem")
        end
      end)
      GemDocs::MCP::Tools::Summary.command(GemDocs::Commands::Summary) if defined?(GemDocs::MCP::Tools::Summary)

      server = described_class.build_fast_mcp_server
      transport = CapturingTransport.new
      server.transport = transport

      server.handle_json_request(
        {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: {
            name: "summary",
            arguments: {
              gem_name: "missing-gem"
            }
          }
        }
      )
      response = transport.messages.last

      expect(response.dig(:result, :isError)).to be(true)
      expect(JSON.parse(response.dig(:result, :content, 0, :text))).to eq(
        "error" => "not_found",
        "message" => "Gem 'missing-gem' is not installed"
      )
    end

    it "publishes MCP input schemas for the supported tool arguments" do
      server = described_class.build_fast_mcp_server
      transport = CapturingTransport.new
      server.transport = transport

      server.handle_json_request(
        {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list"
        }
      )
      response = transport.messages.last
      summary_tool = response.dig(:result, :tools).find { |tool| tool[:name] == "summary" }
      search_tool = response.dig(:result, :tools).find { |tool| tool[:name] == "search" }

      expect(summary_tool.dig(:inputSchema, :required)).to eq([ "gem_name" ])
      expect(summary_tool.dig(:inputSchema, :properties, :version, :type)).to eq("string")
      expect(search_tool.dig(:inputSchema, :properties, :limit, :type)).to eq("integer")
    end
  end

  describe ".start" do
    let(:fast_mcp_server) { instance_double(FastMcp::Server, start: nil) }

    before do
      allow(described_class).to receive(:load_fast_mcp).and_return(true)
      allow(described_class).to receive(:build_fast_mcp_server).and_return(fast_mcp_server)
    end

    it "starts the FastMcp server in stdio mode by default" do
      status = described_class.start([], err: StringIO.new)

      expect(status).to eq(0)
      expect(fast_mcp_server).to have_received(:start)
    end

    it "routes http mode through the HTTP server runner" do
      allow(described_class).to receive(:run_http).and_return(0)

      status = described_class.start([ "--mode", "http", "--port", "7001", "--bind-all" ], err: StringIO.new)

      expect(status).to eq(0)
      expect(described_class).to have_received(:run_http).with(
        fast_mcp_server,
        host: "0.0.0.0",
        port: 7001,
        out: anything
      )
    end
  end
end
