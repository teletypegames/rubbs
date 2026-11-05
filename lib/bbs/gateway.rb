# frozen_string_literal: true

require 'io/wait'
require 'socket'

module BBS
  # A door to another telnet board, the telnet gateway of the old BBSes: the
  # caller's line is handed on to +host+:+port+ as it is, and comes back when
  # that board hangs up. The board on the other end runs its own code; this
  # one only carries the bytes.
  #
  #   door :feedia, BBS::Gateway.new(host: 'feedia.example', port: 2323, name: 'Feedia'), label: '&Feedia'
  #
  # Towards the other board the gateway is the telnet client: it answers its
  # negotiation, reports the caller's window size, and passes the caller's
  # later size changes on. A PETSCII line has no window size to report, so
  # the other board takes it for a Commodore. Everything else goes through
  # untouched both ways, mouse reports and PETSCII included.
  #
  # A gateway is made for one address; a directory that dials many boards
  # makes one a call, and reads how it went from the Report its block gets:
  #
  #   BBS::Gateway.new(host: 'bbs.example.org', port: 23).call(session) do |report|
  #     log(report.connected ? "#{report.received} bytes" : report.error.class)
  #   end
  #
  # The host is resolved once and the call goes to that address, which by
  # default must be on the public internet (BBS::Address.public?): a listing
  # cannot make the board a relay into its own network. A board that dials
  # its neighbours (<tt>host.docker.internal</tt>, a container) says
  # <tt>public_only: false</tt>.
  #
  # A gateway to one of the board's own neighbours can also say who is
  # calling, with <tt>forward: true</tt>: before anything else it sends the
  # other board the caller's face, IP address and this board's name as
  # telnet NEW-ENVIRON variables (Telnet::Environ::FORWARDED), and a rubbs
  # board that takes them from a neighbour skips its terminal question and
  # splash and counts the caller by the real address (Telnet::Forwarded).
  # Never forward to a board of someone else's: it would learn the caller's
  # address.
  class Gateway
    # Seconds to wait for the other board to accept the connection, by
    # default.
    CONNECT_TIMEOUT = 5
    # Seconds to wait for the caller's key before the line goes back to the
    # board.
    BACK_WAIT       = 30

    # How one #call went, given to its block.
    #
    # [connected]       whether the other board accepted the connection
    # [error]           the exception that kept it from connecting
    #                   (SocketError when the name did not resolve,
    #                   Refused for an address that is not public,
    #                   Errno::ECONNREFUSED, IO::TimeoutError or
    #                   Errno::ETIMEDOUT …), +nil+ when it connected
    # [address]         the IP address called, as a String; +nil+ when it
    #                   did not connect
    # [connect_seconds] how long the connection took to open, a Float;
    #                   +nil+ when it did not connect
    # [received]        the bytes the other board sent the caller, telnet
    #                   commands not counted
    # [hung_up]         who ended the crossing: +:board+ or +:caller+;
    #                   +nil+ when it did not connect
    Report = Struct.new(:connected, :error, :address, :connect_seconds, :received, :hung_up, keyword_init: true)

    # Raised (and kept in the Report) when the host resolves to an address
    # a gateway with +public_only+ may not call.
    class Refused < StandardError; end

    # The errors of a call that does not connect.
    FAILURES = [SystemCallError, SocketError, IOError, Refused].freeze

    # The other board's host name, its port as an Integer, and the name
    # shown to the caller.
    attr_reader :host, :port, :name

    # Creates a gateway to +host+:+port+.
    #
    # [name]            the name shown to the caller; defaults to
    #                   <tt>host:port</tt>
    # [terminal]        the terminal type reported to the other board when it
    #                   asks (not on a PETSCII line)
    # [connect_timeout] seconds to wait for the other board to accept the
    #                   connection (CONNECT_TIMEOUT)
    # [idle]            seconds the line may stay silent both ways before
    #                   the call ends as if the caller hung up; +nil+ means
    #                   <tt>BBS.config.idle_seconds</tt>, or
    #                   BBS::Server::DEFAULT_TIMEOUT when that is not set
    # [translate]       whether a PETSCII caller gets the other board through
    #                   an AsciiBridge (a board for ASCII and ANSI terminals);
    #                   the board then sees an ANSI terminal of the C64's
    #                   size. A modern caller's line is never translated.
    # [public_only]     call only an address on the public internet
    #                   (BBS::Address.public?); +false+ for a trusted
    #                   neighbour such as <tt>host.docker.internal</tt>
    # [audience]        the other board's technical name, the +aud+ of the
    #                   RUBBS_AUTH_KEY a forwarding gateway sends a signed-in
    #                   caller's identity in (BBS::Auth::Token); defaults to
    #                   the name's (<tt>TTG Blog BBS</tt> → +ttg-blog-bbs+)
    # [forward]         send the other board who is calling (see above);
    #                   only for a board of one's own
    def initialize(
      host:,
      port:,
      name: nil,
      terminal: 'XTERM-256COLOR',
      connect_timeout: CONNECT_TIMEOUT,
      idle: nil,
      translate: false,
      public_only: true,
      forward: false,
      audience: nil
    )
      @host            = host
      @port            = port.to_i
      @name            = name || "#{host}:#{port}"
      @terminal        = terminal
      @connect_timeout = connect_timeout
      @idle            = idle
      @translate       = translate
      @public_only     = public_only
      @forward         = forward
      @audience        = audience || BoardDefinition.slug(@name)
    end

    # The door's program: connects, carries the line until the other board
    # hangs up, and waits for a key before the board takes the line back.
    # A caller who hangs up meanwhile ends the call (IOError), and so does a
    # line silent both ways for the +idle+ seconds. When the other board
    # does not answer or its address is refused, the caller is told so and
    # the method returns after a key.
    #
    # [session]  the caller's BBS::Session
    # [_context] the caller's context; not used
    #
    # With a block, yields a Report of the call once it is over (also when
    # the caller hung up and the IOError is on its way).
    #
    # Each call writes a +door crossed+ line: the +door+'s name, the +host+
    # (<tt>host:port</tt>), +seconds+ on the other board, who hung up
    # (+by+: +board+ or +caller+) and the +result+ (+ok+, or +failed+ when
    # it did not connect).
    def call(session, _context = {})
      report  = Report.new(connected: false, received: 0)
      started = monotonic
      remote  = connect(session, report) or return
      raise IOError, 'the caller hung up' if carry(session, remote, report)

      back(session, "#{Ansi::RESET}#{Ansi::CRLF * 2}  #{@name} hung up. Press a key to return.")
    ensure
      crossed(report, started) if report
      yield report if block_given? && report
    end

    private

    def crossed(report, started)
      facts = { door: @name, host: "#{@host}:#{@port}", seconds: (monotonic - started).round }
      facts[:by] = report.hung_up.to_s if report.hung_up
      BBS.log('door', 'crossed', **facts, result: report.connected ? 'ok' : 'failed')
    end

    def idle_seconds = @idle || BBS.config.idle_seconds || Server::DEFAULT_TIMEOUT

    # The AsciiBridge of a translated call of a PETSCII caller, or +nil+.
    def bridge(session) = (AsciiBridge.new if @translate && session.petscii?)

    # Opens the connection, filling in +report+; +nil+ when it fails.
    def connect(session, report)
      session.write "#{Ansi::CRLF}  Connecting to #{@name}…#{Ansi::CRLF}"
      started = monotonic
      socket  = open_socket(vetted_ip)
      report.connected       = true
      report.connect_seconds = monotonic - started
      report.address         = socket.remote_address.ip_address
      socket
    rescue *FAILURES => e
      socket&.close rescue nil
      failed(session, report, e)
    end

    # The address of +host+ (an IPv4 one when it has one), resolved once
    # and checked.
    def vetted_ip
      addresses = Addrinfo.getaddrinfo(@host, @port, nil, :STREAM)
      ip = (addresses.find(&:ipv4?) || addresses.first)&.ip_address
      raise SocketError, "#{@host} does not resolve" unless ip
      raise Refused, "#{ip} is not a public address" if @public_only && !Address.public?(ip)

      ip
    end

    def open_socket(ip)
      socket = Socket.tcp(ip, @port, connect_timeout: @connect_timeout)
      error  = socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
      error.zero? ? socket : raise(SystemCallError.new("connect to #{@host}:#{@port}", error))
    end

    def failed(session, report, error)
      report.error = error
      BBS.log('gateway', error, level: :warn, door: @name, host: "#{@host}:#{@port}")
      excuse = error.is_a?(Refused) ? 'may not be called from here' : 'does not answer. Try again later'
      back(session, "#{Ansi::CRLF}  #{@name} #{excuse}. Press a key.")
      nil
    end

    # Carries the line over a Link; true when the caller hung up.
    def carry(session, remote, report)
      remote.write(Telnet::Environ.info(forwarded(session))) if @forward
      link = Link.new(session, remote, terminal: @terminal, idle: idle_seconds, bridge: bridge(session))
      link.run.tap { |hung_up| report.hung_up = hung_up ? :caller : :board }
    ensure
      report.received = link&.received.to_i
      remote.close rescue nil
    end

    # What a forwarding gateway tells the other board: the face it sees
    # (an ANSI terminal for a translated PETSCII caller), the caller's
    # address (as this board believes it), this board's name, and for a
    # signed-in caller their identity in a token for that board.
    def forwarded(session)
      face = session.petscii? && !@translate ? 'petscii' : 'modern'
      {
        'BBS_FACE'       => face,
        'BBS_CLIENT_IP'  => session.caller_ip.to_s,
        'BBS_VIA'        => BBS.config.log_tag.to_s,
        'RUBBS_AUTH_KEY' => auth_key(session)
      }.reject { |_, value| value.to_s.empty? }
    end

    def auth_key(session)
      identity = session.respond_to?(:identity) ? session.identity : nil
      return nil unless identity&.signed_in? && Auth::Token.keys.any?

      Auth::Token.issue(identity, aud: @audience)
    end

    def back(session, text)
      session.write "#{text}#{Ansi::CRLF}"
      session.readkey(timeout: BACK_WAIT)
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

require_relative 'gateway/negotiation'
require_relative 'gateway/link'
