# frozen_string_literal: true

module BBS
  class Gateway
    # One crossing: the bytes of the other board down to the caller, the
    # caller's up to it, each way through its own Telnet::Parser. The other
    # board's telnet commands go to a Negotiation; the caller's window size
    # changes are kept by the session and passed on.
    class Link
      include Telnet::Codes

      # Bytes read from either side at a time.
      CHUNK = 4096
      # A data byte 255, and the same doubled for a telnet line.
      DATA_IAC = [IAC.chr.b, (IAC.chr * 2).b].freeze

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
        @session  = session
        @client   = session.line
        @remote   = remote
        @bridge   = bridge
        @idle     = idle
        @received = 0
        @hung_up  = false
        @heard    = monotonic
        @mu       = Mutex.new
        @negotiation = negotiation(bridge ? 'ANSI' : terminal, session.petscii? && bridge.nil?)
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

      def negotiation(terminal, petscii)
        Negotiation.new(@session, terminal: terminal, petscii: petscii,
                                  remote: ->(bytes) { send_remote(bytes) }, client: ->(bytes) { @client.write(bytes) })
      end

      # The other board's bytes down to the caller, until it hangs up or
      # the line goes silent (counted as the caller hanging up).
      def downstream
        parser = Telnet::Parser.new { |command, argument| @negotiation.command(command, argument) }
        while wait_remote
          data = parser.parse(heard(@remote.readpartial(CHUNK)))
          deliver(data) unless data.empty?
        end
        @hung_up = true
      rescue IOError, SystemCallError
        nil
      end

      # The AsciiBridge doubles a data 255 itself; a plain line gets it
      # doubled here.
      def deliver(data)
        @client.write(@bridge ? @bridge.down(data) : escape(data))
        @received += data.bytesize
      end

      # The caller's bytes up to the other board, until the caller hangs up.
      def upstream
        parser = Telnet::Parser.new { |command, argument| resize(argument) if command == SB }
        loop do
          data = parser.parse(heard(@client.readpartial(CHUNK)))
          data = @bridge.up(data) if @bridge
          send_remote(escape(data)) unless data.empty?
        end
      rescue IOError, SystemCallError
        @hung_up = true
        @remote.shutdown rescue nil
      end

      # The caller's new window size: the board keeps it for after the
      # crossing, and the other board hears it when it asked for NAWS.
      def resize(sub)
        return unless sub[0] == NAWS_OPT && sub.size > Telnet::NAWS_SIZE

        cols = (sub[1] << 8) | sub[2]
        rows = (sub[3] << 8) | sub[4]
        @session.resize!(cols, rows)
        @negotiation.window(cols, rows)
      end

      def escape(data) = data.b.gsub(*DATA_IAC)

      def send_remote(bytes)
        @mu.synchronize { @remote.write(bytes) }
      rescue IOError, SystemCallError
        nil
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

      def heard(bytes)
        @heard = monotonic
        bytes
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
