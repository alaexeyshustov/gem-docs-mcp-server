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

    it "forces delegated tool calls to use JSON formatting" do
      stub_const("GemDocs::Commands::List", Class.new(GemDocs::Commands::Base) do
        def call(format: "text", **)
          out.puts(format)
          0
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
            arguments: {
              format: "text"
            }
          }
        }
      )
      response = transport.messages.last

      expect(response.dig(:result, :isError)).to be(false)
      expect(response.dig(:result, :content, 0, :text)).to eq("json\n")
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

    it "converts unexpected command exceptions into an MCP error result" do
      stub_const("GemDocs::Commands::Lookup", Class.new(GemDocs::Commands::Base) do
        def call(**)
          raise ArgumentError, "boom"
        end
      end)
      GemDocs::MCP::Tools::Lookup.command(GemDocs::Commands::Lookup) if defined?(GemDocs::MCP::Tools::Lookup)

      server = described_class.build_fast_mcp_server
      transport = CapturingTransport.new
      server.transport = transport

      server.handle_json_request(
        {
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: {
            name: "lookup",
            arguments: {
              path: "Widget"
            }
          }
        }
      )
      response = transport.messages.last

      expect(response.dig(:result, :isError)).to be(true)
      expect(JSON.parse(response.dig(:result, :content, 0, :text))).to eq(
        "error" => "internal_error",
        "message" => "boom"
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
        out: anything,
        err: anything
      )
    end
  end

  describe "HTTP request handling" do
    it "returns 408 when the client stops sending request data" do
      socket = instance_double("Socket")
      written_response = +""

      allow(described_class).to receive(:wait_for_socket_data)
        .and_raise(described_class::RequestTimeoutError, "timed out waiting for request data")
      allow(socket).to receive(:write) do |chunk|
        written_response << chunk
      end

      described_class.send(
        :handle_http_connection,
        socket,
        ->(_env) { raise "should not reach app" },
        host: "127.0.0.1",
        port: 6040
      )

      expect(written_response).to include("408 Request Timeout")
    end

    it "returns 413 for request bodies above the configured size limit" do
      socket = instance_double("Socket")
      written_response = +""

      allow(socket).to receive(:gets).with("\r\n").and_return(
        "POST /mcp/messages HTTP/1.1\r\n",
        "Content-Length: #{(10 * 1024 * 1024) + 1}\r\n",
        "\r\n"
      )
      allow(described_class).to receive(:wait_for_socket_data).and_yield
      allow(socket).to receive(:write) do |chunk|
        written_response << chunk
      end

      described_class.send(
        :handle_http_connection,
        socket,
        ->(_env) { raise "should not reach app" },
        host: "127.0.0.1",
        port: 6040
      )

      expect(written_response).to include("413 Payload Too Large")
    end

    it "normalizes request header names before reading the body and building rack env" do
      socket = double("Socket")
      written_response = +""
      received_env = nil

      allow(socket).to receive(:gets).with("\r\n").and_return(
        "POST /mcp/messages HTTP/1.1\r\n",
        "content-length: 7\r\n",
        "content-type: application/json\r\n",
        "\r\n"
      )
      allow(socket).to receive(:read).with(7).and_return("{\"a\":1}")
      allow(described_class).to receive(:wait_for_socket_data).and_yield
      allow(socket).to receive(:peeraddr).with(false).and_return([ nil, nil, nil, "127.0.0.1" ])
      allow(socket).to receive(:write) do |chunk|
        written_response << chunk
      end

      described_class.send(
        :handle_http_connection,
        socket,
        lambda do |env|
          received_env = env
          [ 200, { "Content-Type" => "application/json" }, [ "{\"ok\":true}" ] ]
        end,
        host: "127.0.0.1",
        port: 6040
      )

      expect(received_env.fetch("CONTENT_LENGTH")).to eq("7")
      expect(received_env.fetch("CONTENT_TYPE")).to eq("application/json")
      expect(received_env.fetch("rack.input").read).to eq("{\"a\":1}")
      expect(written_response).to include("200 OK")
    end

    it "returns a structured not found payload" do
      status, headers, body = described_class.send(:not_found_response, "/missing")

      expect(status).to eq(404)
      expect(headers).to eq("Content-Type" => "application/json")
      expect(JSON.parse(body.fetch(0))).to eq(
        "error" => "not_found",
        "message" => "No MCP endpoint matches /missing"
      )
    end

    it "keeps the HTTP accept loop running when a request crashes" do
      listener = instance_double("TCPServer")
      socket = instance_double("Socket", closed?: false)

      accept_calls = 0
      allow(TCPServer).to receive(:open).with("127.0.0.1", 6040).and_yield(listener)
      allow(listener).to receive(:accept) do
        accept_calls += 1
        raise Interrupt if accept_calls > 1

        socket
      end
      allow(described_class).to receive(:warn)
      allow(described_class).to receive(:handle_http_connection)
        .with(socket, :app, host: "127.0.0.1", port: 6040)
        .and_raise(StandardError, "boom")
      allow(socket).to receive(:close)

      expect do
        described_class.send(:serve_http, :app, host: "127.0.0.1", port: 6040, out: StringIO.new)
      end.to raise_error(Interrupt)
    end
  end

  describe ".run_http" do
    it "returns a non-zero status when the HTTP listener cannot bind" do
      fast_mcp_server = instance_double(FastMcp::Server, start_rack: :app)
      out = StringIO.new
      err = StringIO.new

      allow(described_class).to receive(:serve_http)
        .with(:app, host: "127.0.0.1", port: 6040, out: out)
        .and_raise(Errno::EADDRINUSE, "Address already in use")

      status = described_class.send(:run_http, fast_mcp_server, host: "127.0.0.1", port: 6040, out: out, err: err)

      expect(status).to eq(1)
      expect(err.string).to include("gem-docs MCP HTTP server failed to bind 127.0.0.1:6040")
    end
  end
end
