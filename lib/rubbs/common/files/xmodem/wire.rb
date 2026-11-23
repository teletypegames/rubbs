# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Xmodem
        # What both ends of a transfer do on the line (Sender, Receiver): bytes
        # out with 0xFF doubled as a telnet IAC, the cancel sequence, and the
        # wait for the terminal to go quiet before the board reads keys again.
        # It needs +@session+ (raw bytes in and out) and +@telnet+.
        module Wire
          private

          # Writes the cancel sequence and returns +outcome+ once the line is
          # quiet (#settled).
          def abort_with(outcome)
            emit(ABORT)
            settled(outcome)
          end

          # +outcome+, or +:hangup+ when the line dropped while it went quiet.
          def settled(outcome) = quiet ? outcome : :hangup

          # Drops bytes until +seconds+ pass without one, at most +most+
          # seconds; false on hangup.
          def quiet(seconds = QUIET, most = QUIET_MAX)
            deadline = monotonic + most
            while monotonic < deadline
              byte = @session.read_raw_byte(seconds)
              return false if byte.nil?
              return true if byte == :timeout
            end
            true
          rescue IOError, SystemCallError
            false
          end

          # Writes +bytes+ raw, 0xFF doubled on a telnet line.
          def emit(bytes)
            @session.write_raw(@telnet ? bytes.b.gsub(TELNET_IAC, TELNET_IAC * 2) : bytes)
          end

          def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
