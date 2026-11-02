# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bbs'
require 'minitest/autorun'
require 'socket'
require 'tmpdir'
require 'timeout'

# A caller's line: a connected pair of sockets, the board's end and the
# caller's.
class FakeLine
  attr_reader :board, :caller

  def initialize
    @board, @caller = UNIXSocket.pair
  end

  def close
    [@board, @caller].each { |io| io.close unless io.closed? }
  end
end

# A BBS::Session on a FakeLine, with the caller's end at hand.
class FakeSession < BBS::Session
  attr_reader :fake_line

  def initialize(line = FakeLine.new)
    @fake_line = line
    super(line.board)
    @term_cols = 80
    @term_rows = 24
  end

  # What the caller received so far, without waiting.
  def received
    out = +''.b
    loop { out << @fake_line.caller.read_nonblock(65_536) }
  rescue IO::WaitReadable, EOFError
    out
  end
end

# A peer with a given IP address, for code that asks a line where it is.
FakePeer = Struct.new(:ip_address)
# A line that answers remote_address.
FakeSocket = Struct.new(:remote_address)
# A session double with a line and an id.
PeerSession = Struct.new(:line, :session_id) do
  def self.from(ip, id = 'abc') = new(FakeSocket.new(FakePeer.new(ip)), id)
end

# A throwaway HTTP server on 127.0.0.1: each connection gets the bytes the
# handler returns for its request line.
class TinyHTTP
  attr_reader :port

  def initialize(&handler)
    @server = TCPServer.new('127.0.0.1', 0)
    @port   = @server.addr[1]
    @thread = Thread.new { loop { serve(@server.accept, handler) } }
  end

  def url(path) = "http://127.0.0.1:#{@port}#{path}"

  def close
    @thread.kill
    @server.close
  end

  private

  def serve(client, handler)
    Thread.new do
      request = client.gets.to_s
      nil while (line = client.gets) && line != "\r\n"
      handler.call(request.split[1], client)
    rescue IOError, SystemCallError
      nil
    ensure
      client.close
    end
  end
end

# The bytes of an HTTP/1.1 response.
def http_response(status, body, headers = {})
  head = { 'Content-Length' => body.bytesize, 'Connection' => 'close', **headers }
  "HTTP/1.1 #{status} X\r\n#{head.map { |k, v| "#{k}: #{v}\r\n" }.join}\r\n#{body}"
end
