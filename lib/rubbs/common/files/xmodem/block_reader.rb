# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Xmodem
        # The reading of one block for Receiver: its number and the number's
        # complement, its data and its check, the checksum or the CRC-16 as
        # the first block shows (see Receiver). It needs +@session+; +@crc+ is
        # +nil+ until the first block decides it.
        module BlockReader
          # Seconds to wait for each byte inside a block.
          BYTE_WAIT    = 5
          # Seconds to wait, after the first check byte of the first block, for
          # a second one (CRC-16).
          TRAILER_WAIT = 1

          private

          # [number, data] of the block +head+ starts, or +nil+ when its number
          # or its check is wrong or a byte did not come.
          def block(head)
            number = byte!
            complement = byte!
            chunk = bytes!(head == STX ? BLOCK_1K : BLOCK)
            return nil unless number + complement == BYTE_MASK && checked?(chunk)

            [number, chunk]
          rescue Timeout
            nil
          end

          def checked?(chunk)
            first = byte!
            @crc = crc_trailer? if @crc.nil?
            return first == Xmodem.checksum(chunk) unless @crc

            ((first << 8) | byte!) == Zmodem.crc16(chunk)
          end

          # Whether the first block carries a CRC-16: a second check byte
          # comes right after the first one.
          def crc_trailer?
            byte = read(TRAILER_WAIT)
            return false if byte == :timeout

            @pending = byte
            true
          end

          def bytes!(count) = Array.new(count) { byte! }.pack('C*')

          def byte!
            if @pending
              byte = @pending
              @pending = nil
              return byte
            end
            byte = read(BYTE_WAIT)
            raise Timeout if byte == :timeout

            byte
          end

          def read(timeout)
            byte = @session.read_raw_byte(timeout)
            raise Hangup if byte.nil?

            byte
          end
        end
      end
    end
  end
end
