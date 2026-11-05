# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      class Gateway
        # The gateway's side of the telnet negotiation with the other board, as
        # its telnet client: it agrees to echo and go-ahead suppression, reports
        # the caller's window size and terminal type when asked (not for a
        # PETSCII caller, who is a Commodore to the other board), passes BINARY
        # on to the caller, and refuses the rest. Each option is answered once,
        # so a board that asks again gets no loop.
        class Negotiation
          include Telnet::Codes

          # The answer to each telnet command that agrees with it.
          AGREE = { WILL => DO, WONT => DONT, DO => WILL, DONT => WONT }.freeze
          # Telnet TERMINAL-TYPE option code.
          TTYPE = 24
          # TERMINAL-TYPE subnegotiation: the other side asks for the type.
          TTYPE_SEND = 1
          # TERMINAL-TYPE subnegotiation: the type follows.
          TTYPE_IS   = 0
          # The low byte of a 16-bit NAWS value.
          BYTE_MASK  = 0xff

          # Creates the negotiation of one crossing.
          #
          # [session]  the caller's Rubbs::Common::Line::Session, for its window size
          # [terminal] the terminal type reported when the other board asks
          # [petscii]  whether the other board is to take the caller for a
          #            Commodore: no window size, no terminal type
          # [remote]   a callable given the bytes (a String) for the other board
          # [client]   a callable given the bytes for the caller's terminal
          def initialize(session, terminal:, petscii:, remote:, client:)
            @session  = session
            @terminal = terminal
            @petscii  = petscii
            @remote   = remote
            @client   = client
            @answered = {}
            @binary   = { WILL => false, DO => false }
          end

          # Answers one command of the other board, as Telnet::Parser gives it:
          # +argument+ is the option, or the bytes of a subnegotiation.
          def command(command, argument)
            command == SB ? subnegotiation(argument) : answer(command, argument)
          end

          # Tells the other board the caller's new window size, when it asked
          # for it. Returns +nil+.
          def window(cols, rows)
            naws(cols, rows) if @naws
            nil
          end

          private

          def answer(command, option)
            return binary(command) if option == BINARY_OPT
            return if [WONT, DONT].include?(command) || @answered[[command, option]]

            @answered[[command, option]] = true
            command == WILL ? reply_will(option) : reply_do(option)
          end

          def reply_will(option) = send_remote(IAC, [ECHO_OPT, SGA_OPT].include?(option) ? DO : DONT, option)

          def reply_do(option)
            return start_naws if option == NAWS_OPT && !@petscii

            send_remote(IAC, will?(option) ? WILL : WONT, option)
          end

          def will?(option) = option == SGA_OPT || (option == TTYPE && !@petscii)

          def start_naws
            @naws = true
            send_remote(IAC, WILL, NAWS_OPT)
            naws(@session.term_cols, @session.term_rows)
          end

          # A file transfer of the other board (Rubbs::Common::Files::Xmodem) asks for telnet
          # BINARY mode and leaves it after: the gateway agrees, and asks the
          # caller's terminal the same, so its CR bytes stay bytes. Only a change
          # of the mode is answered and passed on.
          def binary(command)
            side = [WILL, WONT].include?(command) ? WILL : DO
            on   = [WILL, DO].include?(command)
            return if @binary[side] == on

            @binary[side] = on
            send_remote(IAC, AGREE.fetch(command), BINARY_OPT)
            @client.call([IAC, command, BINARY_OPT].pack('C*'))
          end

          def subnegotiation(sub)
            return unless sub[0] == TTYPE && sub[1] == TTYPE_SEND && !@petscii

            send_remote(IAC, SB, TTYPE, TTYPE_IS, *@terminal.bytes, IAC, SE)
          end

          def naws(cols, rows)
            size = [cols >> 8, cols & BYTE_MASK, rows >> 8, rows & BYTE_MASK].flat_map { |b| b == IAC ? [IAC, IAC] : [b] }
            send_remote(IAC, SB, NAWS_OPT, *size, IAC, SE)
          end

          def send_remote(*bytes) = @remote.call(bytes.pack('C*'))
        end
      end
    end
  end
end
