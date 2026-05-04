# frozen_string_literal: true

require "json"
require "optparse"
require "socket"
require "stringio"
require "timeout"

module GemDocs
  module MCP
    class Server
      RequestTooLargeError = Class.new(StandardError)
      RequestTimeoutError = Class.new(StandardError)

      DEFAULT_MODE = "stdio"
      DEFAULT_PORT = 6040
      MAX_REQUEST_BODY_BYTES = 10 * 1024 * 1024
      SOCKET_READ_TIMEOUT_SECONDS = 30
      HTTP_STATUS_REASONS = {
        200 => "OK",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        413 => "Payload Too Large",
        500 => "Internal Server Error"
      }.freeze

      def self.start(arguments = [], out: $stdout, err: $stderr)
        return 1 unless load_fast_mcp(err)

        options = parse_options(arguments, err: err)
        return 1 unless options

        server = build_fast_mcp_server
        if options.fetch(:mode) == "http"
          return run_http(
            server,
            host: options.fetch(:bind_all) ? "0.0.0.0" : "127.0.0.1",
            port: options.fetch(:port),
            out: out,
            err: err
          )
        end

        server.start
        0
      end

      def self.build_fast_mcp_server
        require "fast_mcp"
        require "gem_docs/mcp/command_tool"
        require "gem_docs/mcp/tools"

        FastMcp::Server.new(name: "gem-docs", version: GemDocs::VERSION).tap do |server|
          server.register_tools(*GemDocs::MCP::Tools.all)
        end
      end

      def self.load_fast_mcp(err)
        require "fast_mcp"
        true
      rescue LoadError
        err.puts "gem-docs-server requires the optional fast-mcp gem."
        false
      rescue StandardError => e
        err.puts "gem-docs-server failed to load fast-mcp: #{e.class}: #{e.message}"
        false
      end

      private_class_method :load_fast_mcp

      def self.parse_options(arguments, err:)
        options = {
          mode: DEFAULT_MODE,
          port: DEFAULT_PORT,
          bind_all: false
        }

        parser = OptionParser.new do |opts|
          opts.on("--mode MODE", %w[stdio http], "Server transport mode") do |mode|
            options[:mode] = mode
          end
          opts.on("--port PORT", Integer, "HTTP port") do |port|
            options[:port] = port
          end
          opts.on("--bind-all", "Bind HTTP mode to 0.0.0.0") do
            options[:bind_all] = true
          end
        end

        parser.parse!(Array(arguments))
        options
      rescue OptionParser::ParseError => e
        err.puts e.message
        nil
      end
      private_class_method :parse_options

      def self.run_http(server, host:, port:, out:, err:)
        app = server.start_rack(
          lambda { |env| not_found_response(env["PATH_INFO"]) },
          path_prefix: "/mcp",
          localhost_only: host != "0.0.0.0"
        )
        serve_http(app, host: host, port: port, out: out)
        0
      rescue Interrupt
        0
      rescue Errno::EACCES, Errno::EADDRINUSE, Errno::EADDRNOTAVAIL, SocketError => e
        err.puts "gem-docs MCP HTTP server failed to bind #{host}:#{port}: #{e.message}"
        1
      end
      private_class_method :run_http

      def self.serve_http(app, host:, port:, out:)
        TCPServer.open(host, port) do |listener|
          out.puts "gem-docs MCP server listening on http://#{host}:#{port}/mcp"
          loop do
            socket = listener.accept
            handle_http_connection(socket, app, host: host, port: port)
          rescue Interrupt
            raise
          rescue StandardError => e
            warn "gem-docs MCP HTTP server error: #{e.class}: #{e.message}"
          ensure
            socket&.close unless socket&.closed?
          end
        end
      end
      private_class_method :serve_http

      def self.handle_http_connection(socket, app, host:, port:)
        request_line = read_http_line(socket)
        return if request_line.nil?

        method, request_target, server_protocol = request_line.strip.split(" ", 3)
        if method.nil? || request_target.nil?
          return write_http_response(
            socket,
            400,
            json_headers,
            [ JSON.generate(error: "bad_request", message: "Malformed HTTP request line") ]
          )
        end

        headers = read_http_headers(socket)
        body = read_http_body(socket, headers)
        path, query = request_target.to_s.split("?", 2)
        resolved_path = path.to_s.empty? ? "/" : path.to_s

        env = rack_env(
          method: method,
          path: resolved_path,
          query: query.to_s,
          headers: headers,
          body: body,
          host: host,
          port: port,
          server_protocol: server_protocol || "HTTP/1.1",
          remote_addr: remote_addr_for(socket)
        )

        status, response_headers, response_body = app.call(env)
        write_http_response(socket, status, response_headers, response_body)
      rescue RequestTimeoutError
        write_http_response(socket, 408, json_headers, [ JSON.generate(error: "Request Timeout") ])
      rescue RequestTooLargeError
        write_http_response(socket, 413, json_headers, [ JSON.generate(error: "Payload Too Large") ])
      end
      private_class_method :handle_http_connection

      def self.read_http_headers(socket)
        headers = {} # @type var headers: Hash[String, String]

        while (line = read_http_line(socket))
          stripped_line = line.chomp("\r\n")
          break if stripped_line.empty?

          key, value = stripped_line.split(":", 2)
          next if key.nil?

          normalized_key = key.strip.downcase
          next if normalized_key.empty?

          headers[normalized_key] = value.to_s.strip
        end

        headers
      end
      private_class_method :read_http_headers

      def self.read_http_body(socket, headers)
        content_length = headers.fetch("content-length", "0").to_i
        raise RequestTooLargeError, "Request body exceeds #{MAX_REQUEST_BODY_BYTES} bytes" if content_length > MAX_REQUEST_BODY_BYTES
        return "" unless content_length.positive?

        buffer = +""
        while buffer.bytesize < content_length
          bytes_to_read = [ content_length - buffer.bytesize, 16_384 ].min
          chunk = read_http_chunk(socket, bytes_to_read)
          raise RequestTimeoutError, "Connection closed before request body was fully received" if chunk.nil? || chunk.empty?

          buffer << chunk
        end

        buffer
      end
      private_class_method :read_http_body

      def self.read_http_line(socket)
        wait_for_socket_data do
          socket.gets("\r\n")
        end
      end
      private_class_method :read_http_line

      def self.read_http_chunk(socket, bytes_to_read)
        wait_for_socket_data do
          socket.read(bytes_to_read)
        end
      end
      private_class_method :read_http_chunk

      def self.wait_for_socket_data
        Timeout.timeout(SOCKET_READ_TIMEOUT_SECONDS, RequestTimeoutError) do
          yield
        end
      rescue RequestTimeoutError
        raise RequestTimeoutError, "Timed out waiting for request data"
      end
      private_class_method :wait_for_socket_data

      def self.rack_env(method:, path:, query:, headers:, body:, host:, port:, server_protocol:, remote_addr:)
        env = {
          "REQUEST_METHOD" => method,
          "SCRIPT_NAME" => "",
          "PATH_INFO" => path,
          "QUERY_STRING" => query,
          "SERVER_NAME" => host,
          "SERVER_PORT" => port.to_s,
          "SERVER_PROTOCOL" => server_protocol,
          "REMOTE_ADDR" => remote_addr,
          "rack.version" => [ 3, 0 ],
          "rack.url_scheme" => "http",
          "rack.input" => StringIO.new(body),
          "rack.errors" => $stderr,
          "rack.multithread" => false,
          "rack.multiprocess" => false,
          "rack.run_once" => false
        }

        headers.each do |key, value|
          case key
          when "content-length"
            env["CONTENT_LENGTH"] = value
          when "content-type"
            env["CONTENT_TYPE"] = value
          else
            env["HTTP_#{key.upcase.tr('-', '_')}"] = value
          end
        end

        env
      end
      private_class_method :rack_env

      def self.remote_addr_for(socket)
        socket.peeraddr(false)[3]
      rescue IOError, SystemCallError
        "unknown"
      end
      private_class_method :remote_addr_for

      def self.write_http_response(socket, status, headers, body)
        response_body = +""
        body.each do |chunk|
          response_body << chunk.to_s
        end

        normalized_headers = headers.transform_keys(&:to_s)
        normalized_headers["Content-Length"] ||= response_body.bytesize.to_s
        normalized_headers["Connection"] ||= "close"

        socket.write("HTTP/1.1 #{status} #{http_status_reason(status)}\r\n")
        normalized_headers.each do |key, value|
          socket.write("#{key}: #{value}\r\n")
        end
        socket.write("\r\n")
        socket.write(response_body)
      ensure
        body.close if body.respond_to?(:close)
      end
      private_class_method :write_http_response

      def self.http_status_reason(status)
        HTTP_STATUS_REASONS.fetch(status.to_i, "OK")
      end
      private_class_method :http_status_reason

      def self.not_found_response(path)
        [
          404,
          json_headers,
          [ JSON.generate(error: "not_found", message: "No MCP endpoint matches #{path}") ]
        ]
      end
      private_class_method :not_found_response

      def self.json_headers
        { "Content-Type" => "application/json" }
      end
      private_class_method :json_headers
    end
  end
end
