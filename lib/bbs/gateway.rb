# frozen_string_literal: true

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
  class Gateway
    CONNECT_TIMEOUT = 5
    BACK_WAIT       = 30

    attr_reader :host, :port, :name

    def initialize(host:, port:, name: nil, terminal: 'XTERM-256COLOR')
      @host     = host
      @port     = port.to_i
      @name     = name || "#{host}:#{port}"
      @terminal = terminal
    end

    # The door's program: connects, carries the line until the other board
    # hangs up, and waits for a key before the board takes the line back.
    # A caller who hangs up meanwhile ends the call (IOError).
    def call(session, _context = {})
      remote = connect(session) or return
      begin
        hung_up = Link.new(session, remote, terminal: @terminal).run
      ensure
        remote.close rescue nil
      end
      raise IOError, 'the caller hung up' if hung_up

      session.write "\e[0m\r\n\r\n  #{@name} hung up. Press a key to return.\r\n"
      session.readkey(timeout: BACK_WAIT)
    end

    private

    def connect(session)
      session.write "\r\n  Connecting to #{@name}…\r\n"
      socket = Socket.tcp(@host, @port, connect_timeout: CONNECT_TIMEOUT)
      error  = socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
      raise SystemCallError.new("connect to #{@host}:#{@port}", error) unless error.zero?

      socket
    rescue SystemCallError, SocketError, IOError => e
      warn "BBS gateway #{@name} (#{@host}:#{@port}): #{e.class}: #{e.message}"
      session.write "\r\n  #{@name} does not answer. Try again later. Press a key.\r\n"
      session.readkey(timeout: BACK_WAIT)
      nil
    end

    # One crossing: the bytes of the other board down to the caller, the
    # caller's up to it, each way a small telnet state machine.
    class Link
      IAC      = Telnet::IAC
      WILL     = Telnet::WILL
      WONT     = Telnet::WONT
      DO       = Telnet::DO
      DONT     = Telnet::DONT
      SB       = Telnet::SB
      SE       = Telnet::SE
      ECHO_OPT = Telnet::ECHO_OPT
      SGA_OPT  = Telnet::SGA_OPT
      NAWS_OPT = Telnet::NAWS_OPT

      CHUNK = 4096
      TTYPE = 24

      def initialize(session, remote, terminal:)
        @session  = session
        @client   = session.line
        @remote   = remote
        @terminal = terminal
        @petscii  = session.petscii?
        @naws     = false
        @answered = {}
        @mu       = Mutex.new
        @hung_up  = false
      end

      # True when the caller hung up, false when the other board did.
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

      def downstream
        state = :data
        cmd   = nil
        sub   = []
        loop do
          out = +''.b
          @remote.readpartial(CHUNK).each_byte do |b|
            case state
            when :data
              if b == IAC then state = :iac else out << b end
            when :iac
              case b
              when IAC              then out << IAC << IAC; state = :data
              when WILL, WONT, DO, DONT then cmd = b; state = :opt
              when SB               then sub = []; state = :sb
              else state = :data
              end
            when :opt
              answer(cmd, b)
              state = :data
            when :sb
              if b == IAC then state = :sb_iac else sub << b end
            when :sb_iac
              if b == SE
                subnegotiation(sub)
                state = :data
              else
                sub << b if b == IAC
                state = :sb
              end
            end
          end
          @client.write(out) unless out.empty?
        end
      rescue EOFError, IOError, SystemCallError
        nil
      end

      def upstream
        state = :data
        sub   = []
        loop do
          out = []
          @client.readpartial(CHUNK).each_byte do |b|
            case state
            when :data
              if b == IAC then state = :iac else out << b end
            when :iac
              case b
              when IAC              then out << IAC << IAC; state = :data
              when WILL, WONT, DO, DONT then state = :opt
              when SB               then sub = []; state = :sb
              else state = :data
              end
            when :opt
              state = :data
            when :sb
              if b == IAC then state = :sb_iac else sub << b end
            when :sb_iac
              if b == SE
                resize(sub)
                state = :data
              else
                sub << b if b == IAC
                state = :sb
              end
            end
          end
          send_remote(out) unless out.empty?
        end
      rescue EOFError, IOError, SystemCallError
        @hung_up = true
        @remote.shutdown rescue nil
      end

      # Each option is answered once: a board that asks again gets no loop.
      def answer(cmd, opt)
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

      def subnegotiation(sub)
        return unless sub[0] == TTYPE && sub[1] == 1 && !@petscii

        send_remote([IAC, SB, TTYPE, 0, *@terminal.bytes, IAC, SE])
      end

      # The caller's new window size: the board keeps it for after the
      # crossing, and the other board hears it when it asked for NAWS.
      def resize(sub)
        return unless sub[0] == NAWS_OPT && sub.size >= 5

        cols = (sub[1] << 8) | sub[2]
        rows = (sub[3] << 8) | sub[4]
        @session.resize!(cols, rows)
        naws(cols, rows) if @naws
      end

      def naws(cols, rows)
        size = [cols >> 8, cols & 255, rows >> 8, rows & 255].flat_map { |b| b == IAC ? [IAC, IAC] : [b] }
        send_remote([IAC, SB, NAWS_OPT, *size, IAC, SE])
      end
    end
  end
end
