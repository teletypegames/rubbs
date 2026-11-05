# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      module Telnet
        # Telnet commands taken out of a byte stream, one byte at a time: a
        # small state machine, shared by the board's own line (Rubbs::Common::Line::Telnet) and
        # both directions of a Rubbs::Common::Line::Gateway::Link. Data bytes come out, a doubled
        # IAC as one 255; each option command and subnegotiation goes to the
        # block given to ::new.
        #
        #   parser = Rubbs::Common::Line::Telnet::Parser.new { |command, argument| p [command, argument] }
        #   parser.parse("hi\xFF\xFB\x01".b)   # => "hi", and prints [251, 1]
        #
        # The block gets <tt>(command, option)</tt> for WILL, WONT, DO and DONT,
        # and <tt>(SB, bytes)</tt> for a subnegotiation, +bytes+ an Array of
        # Integer whose first is the option; a subnegotiation keeps at most
        # MAX_SUBNEGOTIATION bytes, the rest is read and dropped. Other commands
        # (NOP, GA …) are dropped.
        class Parser
          include Codes

          # The commands followed by one option byte.
          OPTION_COMMANDS = [WILL, WONT, DO, DONT].freeze

          # Creates a parser in the data state; +on_command+ is called as
          # described above.
          def initialize(&on_command)
            @on_command = on_command
            @state      = :data
          end

          # Takes the next byte (an Integer) of the stream. Returns it when it
          # is data, +nil+ when it belongs to a command.
          def feed(byte) = send(@state, byte)

          # Takes a String of bytes and returns its data bytes, a binary String.
          def parse(bytes) = bytes.each_byte.filter_map { |byte| feed(byte) }.pack('C*')

          private

          def data(byte) = byte == IAC ? to(:command) : byte

          def command(byte)
            case byte
            when IAC then to(:data, byte)
            when *OPTION_COMMANDS then option_of(byte)
            when SB then subnegotiation_start
            else to(:data)
            end
          end

          def option_of(command)
            @command = command
            to(:option)
          end

          def option(byte) = emit(@command, byte)

          def subnegotiation_start
            @sub = []
            to(:subnegotiation)
          end

          def subnegotiation(byte) = byte == IAC ? to(:subnegotiation_iac) : keep(byte)

          def subnegotiation_iac(byte)
            return emit(SB, @sub) if byte == SE

            keep(byte) if byte == IAC
            to(:subnegotiation)
          end

          def keep(byte)
            @sub << byte if @sub.size < MAX_SUBNEGOTIATION
            nil
          end

          def emit(command, argument)
            @state = :data
            @on_command&.call(command, argument)
            nil
          end

          def to(state, out = nil)
            @state = state
            out
          end
        end
      end
    end
  end
end
