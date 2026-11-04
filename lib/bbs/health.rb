# frozen_string_literal: true

require 'socket'

module BBS
  # The health probe of a running board, on its own telnet port: a
  # connection from the machine itself (a loopback address) whose first
  # line is REQUEST gets one line back and is closed, without a session,
  # a log line or a count against the caller limits:
  #
  #   OK 3/100                         three callers on, a hundred at most
  #   FAIL database main: SQLite3::…   the board's own health check (BBS.config.health) found a problem
  #
  # A board that does not answer (not listening yet, stopping, hung) is
  # unhealthy too. The +bbs-health+ command asks it, as does
  #
  #   printf 'BBS-HEALTH\r\n' | nc -w 5 127.0.0.1 2323
  #
  # so a container's +HEALTHCHECK+ needs nothing but the board's port.
  module Health
    # The probe's line.
    REQUEST = 'BBS-HEALTH'
    # Seconds a loopback connection is watched for the probe's line before
    # it is taken for a caller.
    WAIT = 0.3

    # Whether +client+, a connection from +address+, is the health probe:
    # a loopback address whose first bytes are REQUEST (read without taking
    # them, so a caller's own first bytes stay on the line).
    def self.probe?(client, address)
      return false unless loopback?(address) && client.respond_to?(:recv_nonblock)
      return false unless client.wait_readable(WAIT)

      bytes = client.recv_nonblock(REQUEST.bytesize, Socket::MSG_PEEK, exception: false)
      bytes.is_a?(String) && bytes == REQUEST
    rescue SystemCallError, IOError
      false
    end

    # Answers the probe on +client+ with #status for +server+ and closes
    # it. Returns +nil+.
    def self.answer(client, server)
      client.write("#{status(server)}\r\n")
    rescue SystemCallError, IOError
      nil
    ensure
      client.close rescue nil
    end

    # The answer for +server+ (a BBS::Server): "OK callers/most", or
    # "FAIL " and the board's problems (BBS.config.health; an error it
    # raises is one).
    def self.status(server)
      problems = problems()
      return "FAIL #{problems.join('; ')}" if problems.any?

      "OK #{server.callers}/#{BBS.config.max_sessions}"
    end

    # The board's problems: what BBS.config.health returns, an Array of
    # Strings, empty when it is well or has no health check.
    def self.problems
      Array(BBS.config.health&.call).map(&:to_s)
    rescue StandardError => e
      ["#{e.class}: #{e.message}"]
    end

    # Whether +address+ is the machine itself (127.0.0.0/8 or ::1).
    def self.loopback?(address)
      ip = Address.parse(address)
      ip = ip.native if ip&.ipv4_mapped?
      !ip.nil? && ip.loopback?
    end

    # Asks the board on +port+ of +host+ (the +bbs-health+ command): the
    # answer line, or the reason there was none. Returns <tt>[ok, line]</tt>.
    def self.ask(port:, host: '127.0.0.1', timeout: 5)
      Socket.tcp(host, port, connect_timeout: timeout) do |socket|
        socket.write("#{REQUEST}\r\n")
        return [false, 'no answer'] unless socket.wait_readable(timeout)

        line = socket.gets.to_s.strip
        [line.start_with?('OK'), line]
      end
    rescue SystemCallError, IOError, SocketError => e
      [false, "#{e.class}: #{e.message}"]
    end
  end
end
