# frozen_string_literal: true

require 'io/wait'
require_relative 'telnet/codes'
require_relative 'telnet/parser'
require_relative 'telnet/mouse'
require_relative 'telnet/keys'
require_relative 'telnet/escapes'
require_relative 'telnet/line_input'
require_relative 'telnet/environ'
require_relative 'telnet/forwarded'

module Rubbs
  module Common
    module Line
      # The telnet line I/O of a Rubbs::Common::Line::Session: option negotiation, key and line
      # input with telnet commands filtered out (Telnet::Parser), ANSI escape and
      # mouse report decoding (Telnet::Keys, Telnet::Mouse), line editing
      # (Telnet::LineInput), window size (NAWS) tracking, and the PETSCII mode
      # for Commodore 64 callers. The including class keeps the socket in
      # +@client+.
      module Telnet
        include Codes
        include Mouse
        include Keys
        include Escapes
        include LineInput
        include Forwarded

        # The widest terminal accepted from a NAWS report, in columns.
        MAX_COLS = 255
        # The tallest terminal accepted from a NAWS report, in rows.
        MAX_ROWS = 100
        # The terminal width assumed while the caller has not reported one.
        DEFAULT_COLS = 80
        # The terminal height assumed while the caller has not reported one.
        DEFAULT_ROWS = 24
        # The narrowest terminal accepted from a NAWS report, in columns.
        MIN_COLS = 20
        # The shortest terminal accepted from a NAWS report, in rows.
        MIN_ROWS = 8
        # The bytes of a NAWS report: width and height, two bytes each.
        NAWS_SIZE = 4
        # The most bytes of a subnegotiation kept; the rest is read and dropped.
        # Room for a NEW-ENVIRON RUBBS_AUTH_KEY (a Rubbs::Common::Auth::Token).
        MAX_SUBNEGOTIATION = 640
        # The opening negotiation: the server will echo and suppress go-ahead,
        # and asks the client to suppress go-ahead and report its window size.
        NEGOTIATION = [IAC, WILL, SGA_OPT, IAC, WILL, ECHO_OPT, IAC, DO, SGA_OPT, IAC, DO, NAWS_OPT].pack('C*').freeze

        # Sets the terminal size to 80x24 until the client reports its own, and
        # sends the opening NEGOTIATION.
        #
        # A line end goes first: the UltimateTerm of the C64 Ultimate takes a
        # line whose first byte is a telnet command (IAC) for ASCII with ANSI and
        # translates every byte from ASCII to PETSCII, which turns CLR into
        # nothing and swaps the case of letters both ways; any other first byte
        # leaves it on PETSCII, printing the bytes as they come.
        def negotiate
          @term_cols = DEFAULT_COLS
          @term_rows = DEFAULT_ROWS
          send_raw Modern::Ansi::CRLF
          send_raw NEGOTIATION
        end

        # Returns true once the client has reported its window size (telnet
        # NAWS). Real terminals do; port scanners and password-guessing bots
        # usually do not.
        def naws_reported? = @naws_reported == true

        # Waits up to +timeout+ seconds for the client's answers to the
        # negotiation, its window size above all, and drops whatever it types
        # meanwhile: a bot's "root" sent before any prompt goes nowhere.
        # Returns +self+ when the window size came, +nil+ when it did not.
        def settle(timeout: 1.5)
          deadline = monotonic + timeout
          until naws_reported?
            left = deadline - monotonic
            raw  = read_byte(left) if left.positive?
            break unless raw.is_a?(String)

            telnet_data(raw.ord)
          end
          self if naws_reported?
        end

        # Switches the line to PETSCII for a Commodore 64 (see Rubbs::Petscii):
        # sets the size to 40x25, sends the codes for the lowercase character set
        # (locked) and a clear screen, and turns mouse reporting off. From then on
        # #write encodes its output and #readkey / #readline decode PETSCII keys.
        # Does nothing when the line is already in PETSCII mode.
        def petscii!
          return if @petscii

          @mouse_enabled = false
          @term_cols     = Petscii::COLS
          @term_rows     = Petscii::ROWS
          send_raw Petscii.bytes("#{Petscii::LOWERCASE}#{Petscii::LOCK_CASE}#{Petscii::CLEAR}")
          @petscii = Petscii::Encoder.new
        end

        # True when the line is in PETSCII mode (see #petscii!).
        def petscii? = !@petscii.nil?

        # Returns the caller's socket itself, for a door that hands it on as it
        # is (Rubbs::Common::Line::Gateway).
        def line = @client

        # Sets the caller's window size from a NAWS report: +cols+ is clamped to
        # MIN_COLS..MAX_COLS and +rows+ to MIN_ROWS..MAX_ROWS, a zero value is
        # ignored, and a PETSCII line keeps 40x25. Marks the size as reported
        # (#naws_reported?).
        def resize!(cols, rows)
          unless @petscii
            @term_cols = cols.clamp(MIN_COLS, MAX_COLS) if cols.positive?
            @term_rows = rows.clamp(MIN_ROWS, MAX_ROWS) if rows.positive?
          end
          @naws_reported = true
        end

        # Writes +data+ (a String) to the caller, encoded to PETSCII on a
        # PETSCII line. Returns +nil+ when the write fails, except for a caller
        # who stopped reading: when the write times out (IO::TimeoutError) the
        # line is closed and IOError is raised, which ends the session.
        def write(data)
          send_raw(@petscii ? @petscii.encode(data) : data)
        rescue IOError
          raise
        rescue StandardError
          nil
        end

        # Writes the bytes of +data+ to the caller as they are, not encoded to
        # PETSCII even on a PETSCII line: for binary protocols (Rubbs::Common::Files::Zmodem,
        # Rubbs::Common::Files::Xmodem) and telnet commands. Fails as #write does.
        def write_raw(data) = send_raw(data)

        private

        # Reads one raw byte as a one-byte String; +:timeout+ when nothing came
        # within +timeout+ seconds (+nil+: wait forever), +nil+ on hangup.
        def read_byte(timeout = nil)
          return @client.read(1) if timeout.nil?
          return :timeout unless @client.wait_readable(timeout)

          @client.read(1)
        end

        # Passes +byte+ through the line's Parser: the byte when it is data,
        # +nil+ when it belongs to a telnet command.
        def telnet_data(byte) = telnet_parser.feed(byte)

        def telnet_parser = @telnet_parser ||= Parser.new { |command, argument| telnet_command(command, argument) }

        # A NAWS report resizes the line, NEW-ENVIRON variables are kept
        # (Telnet::Forwarded); the other commands need no answer.
        def telnet_command(command, argument)
          return unless command == SB
          return take_environ(argument) if argument[0] == NEW_ENVIRON_OPT
          return unless argument[0] == NAWS_OPT && argument.size > NAWS_SIZE

          resize!((argument[1] << 8) | argument[2], (argument[3] << 8) | argument[4])
        end

        def send_raw(data)
          @client.write(data)
        rescue IO::TimeoutError
          @client.close rescue nil
          raise IOError, 'the caller stopped reading'
        rescue StandardError
          nil
        end

        def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
