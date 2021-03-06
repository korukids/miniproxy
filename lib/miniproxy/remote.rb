require "miniproxy/stub/request"
require "miniproxy/stub/response"
require "miniproxy/proxy_server"
require "miniproxy/fake_ssl_server"

module MiniProxy
  # Controls the remote DRb service, which provides a communcation mechanism
  #
  class Remote
    SERVER_DYNAMIC_PORT_RANGE = (12345..32768).to_a.freeze
    SERVER_START_TIMEOUT = 10

    def self.pid
      @pid
    end

    def self.drb_process_alive?
      pid && Process.kill(0, pid) == 1
    rescue Errno::ESRCH
      false
    end

    def self.server(host = "127.0.0.1")
      @unix_socket_uri ||= begin
        tempfile = Tempfile.new("mini_proxy")
        socket_path = tempfile.path
        tempfile.close!
        "drbunix:///#{socket_path}"
      end

      return @unix_socket_uri if drb_process_alive?

      @pid = fork do
        remote = Remote.new

        Timeout.timeout(SERVER_START_TIMEOUT) do
          begin
            fake_server_port = SERVER_DYNAMIC_PORT_RANGE.sample
            fake_server = FakeSSLServer.new(
              MiniProxyHost: host,
              Port: fake_server_port,
              MockHandlerCallback: remote.method(:handler),
            )
            Thread.new { fake_server.start }
          rescue Errno::EADDRINUSE
            retry
          end

          begin
            remote.port = ENV["MINI_PROXY_PORT"] || SERVER_DYNAMIC_PORT_RANGE.sample
            proxy = MiniProxy::ProxyServer.new(
              MiniProxyHost: host,
              Port: remote.port,
              FakeServerPort: fake_server_port,
              MockHandlerCallback: remote.method(:handler),
            )
            Thread.new { proxy.start }
          rescue Errno::EADDRINUSE
            retry
          end
        end

        DRb.start_service(@unix_socket_uri, remote)
        DRb.thread.join

        Process.exit!
      end

      Process.detach(@pid)
      @unix_socket_uri
    end

    def handler(req, res)
      if (request = @stubs.detect { |mock_request| mock_request.match?(req) })
        response = request.response
        res.status = response.code
        response.headers.each { |key, value| res[key] = value }
        res.body = response.body
      else
        res.status = 200
        res.body = ""
        queue_message "WARN: external request to #{req.host}#{req.path} not mocked"
        queue_message %Q{Stub with: MiniProxy.stub_request(method: "#{req.request_method}", url: "#{req.host}#{req.path}")}
      end
    end

    def stub_request(method:, url:, response:)
      response = MiniProxy::Stub::Response.new(headers: response[:headers], body: response[:body])
      request = MiniProxy::Stub::Request.new(method: method, url: url, response: response)
      @stubs.push(request)
    end

    def port
      @port
    end

    def port=(value)
      @port = value
    end

    def stop
      DRb.stop_service
    end

    def clear
      @stubs.clear
    end

    def drain_messages
      @messages.slice!(0, @messages.length)
    end

    def started?
      current_server = DRb.current_server()
      current_server && current_server.alive?
    end

    private

    def queue_message(msg)
      @messages.push msg
    end

    def initialize
      @stubs = []
      @messages = []
    end
  end
end
