# frozen_string_literal: true

require 'socket'

module BBS
  # The telnet listener. It accepts connections on a TCP port and runs a
  # BBS::Session for each caller in its own thread, up to
  # <tt>BBS.config.max_sessions</tt> callers at once.
  #
  #   BBS::Server.new(port: 2323).run
  class Server
    # Seconds a silent line may stay connected when
    # <tt>BBS.config.idle_seconds</tt> is not set.
    DEFAULT_TIMEOUT = 900

    # Creates a server that will listen on +port+ on all interfaces. Nothing
    # is opened until #run.
    def initialize(port:)
      @port     = port
      @mu       = Mutex.new
      @sessions = 0
    end

    # Opens the port and serves callers until the process is interrupted.
    # Blocks the calling thread.
    #
    # Each accepted connection gets an idle timeout and a BBS::Session in a
    # new thread. A caller over the session limit is told the board is busy
    # and disconnected. Session errors are logged and end only that session;
    # <tt>BBS.config.on_session_end</tt> is called with the session when it
    # finishes. On Interrupt it prints "Server stopped." and returns.
    def run
      server = TCPServer.new('0.0.0.0', @port)
      puts "BBS listening on port #{@port} — connect with: telnet localhost #{@port}"
      loop do
        client = begin
          server.accept
        rescue Errno::ECONNABORTED, Errno::EMFILE, Errno::ENFILE, IOError => e
          warn "BBS accept error: #{e.class}: #{e.message}"
          sleep 0.5
          next
        end

        unless admit
          # One line per turned-away caller, so a log pipeline can count them.
          warn "BBS busy: #{BBS.config.max_sessions} callers on, turned one away"
          client.write("Too many callers right now, try again later.\r\n") rescue nil
          client.close rescue nil
          next
        end

        Thread.new(client) do |c|
          # A line that stays silent (or stops reading) longer than the idle
          # limit is dropped, at a login prompt or inside a door alike.
          c.timeout = BBS.config.idle_seconds || DEFAULT_TIMEOUT if c.respond_to?(:timeout=)
          session = Session.new(c)
          begin
            session.run
          rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ETIMEDOUT, IO::TimeoutError => e
            # The client hung up or went silent: an ordinary end of a session, not a fault.
            puts "BBS session dropped by the client (#{e.message})"
          rescue StandardError => e
            warn "BBS session error: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
          ensure
            @mu.synchronize { @sessions -= 1 }
            BBS.config.on_session_end&.call(session)
          end
        end
      end
    rescue Interrupt
      puts "\nServer stopped."
    end

    private

    def admit
      @mu.synchronize do
        return false if @sessions >= BBS.config.max_sessions

        @sessions += 1
        true
      end
    end
  end
end
