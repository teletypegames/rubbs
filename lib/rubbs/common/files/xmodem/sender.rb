# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Xmodem
        # One XMODEM send over a session. Xmodem.send_file is the usual way in.
        class Sender
          include Wire

          # Creates a sender writing to and reading raw bytes from +session+;
          # +telnet+ doubles 0xFF bytes as telnet IAC and asks for BINARY mode.
          def initialize(session, telnet: true)
            @session = session
            @telnet  = telnet
          end

          # Sends +data+ (as for Xmodem.send_file): waits up to +wait+ seconds
          # for the receiver's +C+ or NAK (other bytes are skipped), sends the
          # blocks one by one, each again on a NAK or silence, then the EOT.
          # Writes the cancel sequence when the transfer is given up. Before it
          # returns, drops what the terminal still sends until the line is quiet
          # (QUIET, at most QUIET_MAX seconds).
          #
          # Returns +:ok+, +:cancelled+, +:timeout+ or +:hangup+.
          def run(data, one_k:, wait:)
            @session.write_raw(BINARY_ON) if @telnet
            send_blocks(data, one_k, wait)
            settled(:ok)
          rescue Cancelled
            abort_with(:cancelled)
          rescue Timeout
            abort_with(:timeout)
          rescue Hangup, IOError, SystemCallError
            :hangup
          ensure
            @session.write_raw(BINARY_OFF) if @telnet
          end

          private

          # The blocks of +data+ (1 KiB ones when +one_k+ and the receiver asks
          # for a CRC), then EOT.
          def send_blocks(data, one_k, wait)
            crc  = handshake(wait)
            size = crc && one_k ? BLOCK_1K : BLOCK
            Xmodem.blocks(data, size).each.with_index(1) do |chunk, number|
              deliver(Xmodem.frame(number % BLOCK_NUMBERS, chunk, crc: crc))
            end
            deliver(EOT.chr)
          end

          def handshake(wait)
            deadline = monotonic + wait
            loop do
              left = deadline - monotonic
              raise Timeout if left <= 0

              case read(left)
              when :timeout then raise Timeout
              when CRC_START then return true
              when NAK then return false
              when *CANCEL_KEYS then raise Cancelled
              end
            end
          end

          def deliver(bytes)
            TRIES.times do
              emit(bytes)
              case answer
              when ACK then return
              when :timeout, NAK then next
              end
            end
            raise Timeout
          end

          def answer
            deadline = monotonic + BLOCK_WAIT
            loop do
              left = deadline - monotonic
              return :timeout if left <= 0

              byte = read(left)
              return byte if [ACK, NAK, :timeout].include?(byte)
            end
          end

          def read(timeout)
            byte = @session.read_raw_byte(timeout)
            raise Hangup if byte.nil?

            @cans = byte == CAN ? @cans.to_i + 1 : 0
            raise Cancelled if @cans >= CANCEL_COUNT

            byte
          end
        end
      end
    end
  end
end
