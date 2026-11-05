# frozen_string_literal: true

require 'socket'
require_relative 'server/stopping'
require_relative 'server/calls'

module BBS
  # The telnet listener. It accepts connections on a TCP port and runs a
  # BBS::Session for each caller in its own thread, up to
  # <tt>BBS.config.max_sessions</tt> callers at once and
  # <tt>BBS.config.max_sessions_per_ip</tt> from one public address.
  #
  #   BBS::Server.new(port: 2323).run
  class Server
    include Stopping
    include Calls

    # Seconds a silent line may stay connected when
    # <tt>BBS.config.idle_seconds</tt> is not set.
    DEFAULT_TIMEOUT = 900
    # Seconds the accept loop rests after a failed accept (out of file
    # descriptors and the like).
    ACCEPT_PAUSE = 0.5
    # What a caller turned away hears, by the verdict of #admit.
    REFUSALS = {
      busy:    'Too many callers right now, try again later.',
      crowded: 'Too many calls from your address, try again later.'
    }.freeze
    # Creates a server that will listen on +port+ on all interfaces. Nothing
    # is opened until #run.
    def initialize(port:)
      @port     = port
      @mu       = Mutex.new
      @sessions = 0
      @calls    = Hash.new(0)
      @live     = {}
      @stopping = false
    end

    # Opens the port and serves callers until the process is interrupted
    # (Ctrl-C) or stopped (SIGTERM, as <tt>docker stop</tt> sends), then
    # stops in order (#stop). Blocks the calling thread.
    #
    # Each accepted connection gets an idle timeout and a BBS::Session in a
    # new thread. A caller #admit refuses hears why and is disconnected;
    # the health probe (BBS::Health) gets its answer. Session errors are
    # logged and end only that session; <tt>BBS.config.on_session_end</tt>
    # is called with the session when it finishes, and one log line tells
    # how long the call lasted and how it ended. An error of the accept
    # loop itself is logged as +:fatal+ and raised, so the process ends and
    # its supervisor (Docker's restart policy) starts it again.
    def run
      @listener = TCPServer.new('0.0.0.0', @port)
      @port     = @listener.addr[1]
      BBS.log('server', "listening on port #{@port}", port: @port, rubbs: BBS.version)
      Server.current = self
      stop_on_term
      loop { serve(accept(@listener)) }
    rescue Interrupt
      stop
    rescue StandardError => e
      BBS.log('server', e, level: :fatal)
      raise
    ensure
      @listener&.close rescue nil
    end

    # The port it listens on: once #run has opened it, the one the system
    # chose for port 0.
    attr_reader :port

    # The number of callers on the line now.
    def callers = @mu.synchronize { @sessions }

    # The calls on the line now: their BBS::Session objects, the earliest
    # first (BBS::Session#started_at). A sysop's screen lists them
    # (BBS.calls) and can hang one up (BBS::Session#hang_up).
    def live = @mu.synchronize { @live.values }.sort_by(&:started_at)

    class << self
      # The server whose #run is serving callers in this process, or +nil+
      # before one starts. BBS.calls asks it.
      attr_accessor :current
    end

    # Takes a call from the IP +address+ (a String, +nil+ when unknown) when
    # there is room, and counts it. Returns the verdict:
    #
    # [+:ok+]      admitted; #release must follow when the call ends
    # [+:busy+]    <tt>BBS.config.max_sessions</tt> callers are on
    # [+:crowded+] <tt>BBS.config.max_sessions_per_ip</tt> calls come from
    #              this address already; a local one (a proxy such as
    #              bbs-web on the Docker network, see BBS::Address.local?)
    #              or an unknown one has no such limit
    def admit(address)
      @mu.synchronize do
        return :busy if @sessions >= BBS.config.max_sessions
        return :crowded if crowded?(address)

        @sessions += 1
        @calls[address] += 1
        :ok
      end
    end

    # Ends the count of a call #admit took from +address+.
    def release(address)
      @mu.synchronize do
        @sessions -= 1
        @calls[address] -= 1
        @calls.delete(address) unless @calls[address].positive?
      end
    end

    private

    # An address that is no IP address (a test's pipe) is not limited.
    def crowded?(address)
      return false if Address.parse(address).nil? || Address.local?(address)

      @calls[address] >= BBS.config.max_sessions_per_ip
    end

    def stop_on_term
      runner = Thread.current
      Signal.trap('TERM') { runner.raise(Interrupt) }
    end

    def accept(server)
      server.accept
    rescue SystemCallError, IOError => e
      BBS.log('accept', e, level: :warn)
      sleep ACCEPT_PAUSE
      nil
    end

    def serve(client)
      return unless client

      Thread.new { take(client) }
    end

    # A new connection: the health probe, a caller turned away, or a call.
    def take(client)
      address = peer(client)
      return Health.answer(client, self) if Health.probe?(client, address)

      verdict = admit(address)
      return refuse(client, address, verdict) unless verdict == :ok

      converse(client, address)
    end

    # A line that stays silent (or stops reading) longer than the idle limit
    # is dropped, at a login prompt or inside a door alike.
    def timed(client)
      client.timeout = BBS.config.idle_seconds || DEFAULT_TIMEOUT if client.respond_to?(:timeout=)
      client
    end

    def peer(client)
      client.remote_address.ip_address
    rescue StandardError
      nil
    end

    # One line per turned-away caller, so a log pipeline can count them: it
    # holds "BBS busy" or "BBS crowded" (the Grafana BBS: Overview board counts
    # those).
    def refuse(client, address, verdict)
      BBS.log(
        "BBS #{verdict}",
        "#{BBS.config.max_sessions} callers at most, " \
        "#{BBS.config.max_sessions_per_ip} from one address; turned #{address} away",
        level: :warn
      )
      client.write("#{REFUSALS.fetch(verdict)}#{Ansi::CRLF}") rescue nil
      client.close rescue nil
    end
  end
end
