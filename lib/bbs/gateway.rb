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
    def initialize(host:, port:, name: nil, terminal: 'XTERM-256COLOR', connect_timeout: CONNECT_TIMEOUT, idle: nil,
                   translate: false)
      @host            = host
      @port            = port.to_i
      @name            = name || "#{host}:#{port}"
      @terminal        = terminal
      @connect_timeout = connect_timeout
      @idle            = idle
      @translate       = translate
    end

    # The door's program: connects, carries the line until the other board
    # hangs up, and waits for a key before the board takes the line back.
    # A caller who hangs up meanwhile ends the call (IOError), and so does a
    # line silent both ways for the +idle+ seconds. When the
    # other board does not answer, the caller is told so and the method
    # returns after a key.
    #
    # [session]  the caller's BBS::Session
    # [_context] the caller's context; not used
    #
    # With a block, yields a Report of the call once it is over (also when
    # the caller hung up and the IOError is on its way).
    def call(session, _context = {})
      report = Report.new(connected: false, received: 0)
      remote = connect(session, report) or return
      begin
        link = Link.new(session, remote, terminal: @terminal, idle: idle_seconds, bridge: bridge(session))
        hung_up = link.run
        report.hung_up = hung_up ? :caller : :board
      ensure
        report.received = link&.received.to_i
        remote.close rescue nil
      end
      raise IOError, 'the caller hung up' if hung_up

      session.write "#{Ansi::RESET}#{Ansi::CRLF * 2}  #{@name} hung up. Press a key to return.#{Ansi::CRLF}"
      session.readkey(timeout: BACK_WAIT)
    ensure
      yield report if block_given? && report
    end

    private

    def idle_seconds = @idle || BBS.config.idle_seconds || Server::DEFAULT_TIMEOUT

    # The AsciiBridge of a translated call of a PETSCII caller, or +nil+.
    def bridge(session) = (AsciiBridge.new if @translate && session.petscii?)

    def connect(session, report)
      session.write "#{Ansi::CRLF}  Connecting to #{@name}…#{Ansi::CRLF}"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      socket = Socket.tcp(@host, @port, connect_timeout: @connect_timeout)
      error  = socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
      raise SystemCallError.new("connect to #{@host}:#{@port}", error) unless error.zero?

      report.connected       = true
      report.connect_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      report.address         = (socket.remote_address.ip_address rescue nil)
      socket
    rescue SystemCallError, SocketError, IOError => e
      socket&.close rescue nil
      report.error = e
      warn "BBS gateway #{@name} (#{@host}:#{@port}): #{e.class}: #{e.message}"
      session.write "#{Ansi::CRLF}  #{@name} does not answer. Try again later. Press a key.#{Ansi::CRLF}"
      session.readkey(timeout: BACK_WAIT)
      nil
    end

    # One crossing: the bytes of the other board down to the caller, the
    # caller's up to it, each way a small telnet state machine.
    class Link
      # Telnet "interpret as command" byte (BBS::Telnet::IAC).
      IAC      = Telnet::IAC
      # Telnet WILL command byte.
      WILL     = Telnet::WILL
      # Telnet WONT command byte.
      WONT     = Telnet::WONT
      # Telnet DO command byte.
      DO       = Telnet::DO
      # Telnet DONT command byte.
      DONT     = Telnet::DONT
      # Telnet subnegotiation begin byte.
      SB       = Telnet::SB
      # Telnet subnegotiation end byte.
      SE       = Telnet::SE
      # Telnet ECHO option code.
      ECHO_OPT = Telnet::ECHO_OPT
      # Telnet SUPPRESS-GO-AHEAD option code.
      SGA_OPT  = Telnet::SGA_OPT
      # Telnet NAWS (window size) option code.
      NAWS_OPT = Telnet::NAWS_OPT
      # Telnet BINARY option code, passed on to the caller (see #binary).
      BINARY_OPT = Telnet::BINARY_OPT
      # The answer to each telnet command that agrees with it.
      AGREE = { WILL => DO, WONT => DONT, DO => WILL, DONT => WONT }.freeze

      # Bytes read from either side at a time.
      CHUNK = 4096
      # Telnet TERMINAL-TYPE option code.
      TTYPE = 24
      # TERMINAL-TYPE subnegotiation: the other side asks for the type.
      TTYPE_SEND = 1
      # TERMINAL-TYPE subnegotiation: the type follows.
      TTYPE_IS   = 0
      # The low byte of a 16-bit NAWS value.
      BYTE_MASK  = 0xff

      # The bytes the other board sent the caller so far, telnet commands
      # not counted.
      attr_reader :received

      # Creates a link between the caller's +session+ and the +remote+
      # socket of the other board. +terminal+ is the terminal type reported
      # when the other board asks; +idle+ the seconds the line may stay
      # silent both ways (+nil+: no limit); +bridge+ an AsciiBridge that
      # translates both ways (+nil+: the bytes cross as they are), behind
      # which a PETSCII caller is an ANSI terminal to the other board.
      def initialize(session, remote, terminal:, idle: nil, bridge: nil)
        @received = 0
        @session  = session
        @client   = session.line
        @remote   = remote
        @terminal = bridge ? 'ANSI' : terminal
        @bridge   = bridge
        @petscii  = session.petscii? && bridge.nil?
        @naws     = false
        @answered = {}
        @binary   = { WILL => false, DO => false }
        @mu       = Mutex.new
        @hung_up  = false
        @idle     = idle
        @heard    = monotonic
      end

      # Carries the bytes both ways until one side hangs up: the other
      # board's down to the caller in this thread, the caller's up in a new
      # one.
      #
      # Returns true when the caller hung up or the line stayed silent both
      # ways for the +idle+ seconds, false when the other board hung up.
      # The caller's side ends by shutting the other board's socket down,
      # which wakes the reader of this thread; it is closed by the gateway,
      # never by a thread that may be killed halfway through closing it.
      def run
        up = Thread.new { upstream }
        downstream
        @hung_up
      ensure
        up.kill unless up.nil? || (@hung_up && up.join(1))
      end

      private

      def send_remote(bytes)
        @mu.synchronize { @remote.write(bytes.pack('C*')) }
      rescue IOError, SystemCallError
        nil
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def heard(bytes)
        @heard = monotonic
        bytes
      end

      # Waits for the other board's bytes; false once the line has been
      # silent both ways for the idle seconds.
      def wait_remote
        return true if @idle.nil?

        loop do
          left = @heard + @idle - monotonic
          return false unless left.positive?
          return true if @remote.wait_readable(left)
        end
      end

      def downstream
        state = :data
        cmd   = nil
        sub   = []
        loop do
          return silent unless wait_remote

          out = +''.b
          heard(@remote.readpartial(CHUNK)).each_byte do |b|
            case state
            when :data
              if b == IAC then state = :iac else out << b end
            when :iac
              case b
              when IAC then out << data_iac; state = :data
              when WILL, WONT, DO, DONT then cmd = b; state = :opt
              when SB then sub = []; state = :sb
              else state = :data
              end
            when :opt
              answer(cmd, b)
              state = :data
            when :sb
              if b == IAC then state = :sb_iac else add(sub, b) end
            when :sb_iac
              if b == SE
                subnegotiation(sub)
                state = :data
              else
                add(sub, b) if b == IAC
                state = :sb
              end
            end
          end
          next if out.empty?

          @client.write(@bridge ? @bridge.down(out) : out)
          @received += out.bytesize
        end
      rescue EOFError, IOError, SystemCallError
        nil
      end

      def upstream
        state = :data
        sub   = []
        loop do
          out = []
          heard(@client.readpartial(CHUNK)).each_byte do |b|
            case state
            when :data
              if b == IAC then state = :iac else out << b end
            when :iac
              case b
              when IAC then out << IAC << IAC; state = :data
              when WILL, WONT, DO, DONT then state = :opt
              when SB then sub = []; state = :sb
              else state = :data
              end
            when :opt
              state = :data
            when :sb
              if b == IAC then state = :sb_iac else add(sub, b) end
            when :sb_iac
              if b == SE
                resize(sub)
                state = :data
              else
                add(sub, b) if b == IAC
                state = :sb
              end
            end
          end
          out = @bridge.up(out.pack('C*')).bytes if @bridge
          send_remote(out) unless out.empty?
        end
      rescue EOFError, IOError, SystemCallError
        @hung_up = true
        @remote.shutdown rescue nil
      end

      # A data byte 255 from the other board: doubled again for the caller's
      # telnet client, or single for the AsciiBridge, which doubles what it
      # sends down itself.
      def data_iac = @bridge ? IAC.chr : (IAC.chr * 2)

      # A subnegotiation keeps at most Telnet::MAX_SUBNEGOTIATION bytes; the
      # rest is read and dropped.
      def add(sub, byte)
        sub << byte if sub.size < Telnet::MAX_SUBNEGOTIATION
      end

      # The line went silent both ways: counted as the caller hanging up;
      # #run stops the caller's reader.
      def silent
        @hung_up = true
        nil
      end

      # Each option is answered once: a board that asks again gets no loop.
      # BINARY goes on to the caller instead (#binary).
      def answer(cmd, opt)
        return binary(cmd) if opt == BINARY_OPT
        return if [WONT, DONT].include?(cmd) || @answered[[cmd, opt]]

        @answered[[cmd, opt]] = true
        if cmd == WILL
          send_remote([IAC, [ECHO_OPT, SGA_OPT].include?(opt) ? DO : DONT, opt])
        elsif opt == NAWS_OPT && !@petscii
          @naws = true
          send_remote([IAC, WILL, NAWS_OPT])
          naws(@session.term_cols, @session.term_rows)
        elsif opt == SGA_OPT || (opt == TTYPE && !@petscii)
          send_remote([IAC, WILL, opt])
        else
          send_remote([IAC, WONT, opt])
        end
      end

      # A file transfer of the other board (BBS::Xmodem) asks for telnet
      # BINARY mode and leaves it after: the gateway agrees, and asks the
      # caller's terminal the same, so its CR bytes stay bytes. Only a change
      # of the mode is answered and passed on.
      def binary(cmd)
        side = [WILL, WONT].include?(cmd) ? WILL : DO
        on   = [WILL, DO].include?(cmd)
        return if @binary[side] == on

        @binary[side] = on
        send_remote([IAC, AGREE.fetch(cmd), BINARY_OPT])
        @client.write([IAC, cmd, BINARY_OPT].pack('C*'))
      end

      def subnegotiation(sub)
        return unless sub[0] == TTYPE && sub[1] == TTYPE_SEND && !@petscii

        send_remote([IAC, SB, TTYPE, TTYPE_IS, *@terminal.bytes, IAC, SE])
      end

      # The caller's new window size: the board keeps it for after the
      # crossing, and the other board hears it when it asked for NAWS.
      def resize(sub)
        return unless sub[0] == NAWS_OPT && sub.size >= 1 + Telnet::NAWS_SIZE

        cols = (sub[1] << 8) | sub[2]
        rows = (sub[3] << 8) | sub[4]
        @session.resize!(cols, rows)
        naws(cols, rows) if @naws
      end

      def naws(cols, rows)
        size = [cols >> 8, cols & BYTE_MASK, rows >> 8, rows & BYTE_MASK].flat_map { |b| b == IAC ? [IAC, IAC] : [b] }
        send_remote([IAC, SB, NAWS_OPT, *size, IAC, SE])
      end
    end
  end
end
