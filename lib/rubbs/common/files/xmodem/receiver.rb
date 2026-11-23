# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Xmodem
        # One XMODEM receive over a session. Xmodem.receive_file is the usual
        # way in.
        #
        # The board asks for the start (+C+ for CRC-16 the first CRC_TRIES
        # times, then NAK for the checksum) every START_EVERY seconds. The
        # first block decides the check: a second byte after its first check
        # byte within BlockReader::TRAILER_WAIT means CRC-16, none means the checksum, so a
        # sender that answered either kind of start is read right. A broken
        # block or a silence is asked for again with a NAK (at most TRIES times
        # in a row), a block sent twice (its ACK lost) is acknowledged and
        # dropped, a block out of order ends the transfer.
        #
        # Inside a block every byte is data, so only two CANs where a block
        # should start cancel.
        class Receiver
          include Wire
          include BlockReader

          # Seconds between two start bytes while the board waits for the
          # sender.
          START_EVERY  = 3
          # The start bytes that ask for CRC-16 (+C+) before the board asks for
          # the checksum (NAK).
          CRC_TRIES    = 4
          # Seconds of silence that end the bytes of a broken block, before
          # the board asks for it again.
          PURGE_QUIET  = 1

          # Creates a receiver reading raw bytes from and writing to +session+;
          # +telnet+ takes a doubled 0xFF as one byte and asks for BINARY mode.
          def initialize(session, telnet: true)
            @session = session
            @telnet  = telnet
          end

          # Receives a file (as for Xmodem.receive_file): waits up to +wait+
          # seconds for the first block, takes blocks until the EOT, at most
          # +max_bytes+ bytes and +limit+ seconds. Writes the cancel sequence
          # when the transfer is given up. Before it returns, drops what the
          # terminal still sends until the line is quiet; a line that drops
          # after the end of the file still gives the file.
          #
          # Returns the bytes (a binary String), or +:cancelled+, +:timeout+,
          # +:too_large+, +:failed+ or +:hangup+.
          def run(max_bytes:, wait:, limit:)
            @session.write_raw(BINARY_ON) if @telnet
            receive(max_bytes, wait, limit).tap { quiet }
          rescue Cancelled
            abort_with(:cancelled)
          rescue Timeout
            abort_with(:timeout)
          rescue TooLarge
            abort_with(:too_large)
          rescue Failed
            abort_with(:failed)
          rescue Hangup, IOError, SystemCallError
            :hangup
          ensure
            @session.write_raw(BINARY_OFF) if @telnet
          end

          private

          def receive(max_bytes, wait, limit)
            data = +''.b
            head = start(wait)
            @deadline = monotonic + limit
            @next     = 1
            @errors   = 0
            until head == EOT
              take(head, data, max_bytes)
              head = next_head
            end
            emit(ACK.chr)
            data
          end

          # Waits for the first block's start byte (or an EOT: an empty file),
          # asking for it every START_EVERY seconds.
          def start(wait)
            deadline = monotonic + wait
            tries = 0
            loop do
              left = deadline - monotonic
              raise Timeout if left <= 0

              emit((tries < CRC_TRIES ? CRC_START : NAK).chr)
              tries += 1
              head = head_within([START_EVERY, left].min, keys: true)
              return head if head
            end
          end

          # The start byte of the next block (or EOT), asking again with a NAK
          # after BLOCK_WAIT seconds of silence.
          def next_head
            loop do
              raise Timeout if monotonic > @deadline

              head = head_within(BLOCK_WAIT)
              return head if head

              refuse(Timeout)
            end
          end

          # SOH, STX or EOT when one comes within +seconds+, else +nil+; other
          # bytes are skipped, two CANs in a row cancel, and with +keys+ Esc or
          # Ctrl-C cancels too.
          def head_within(seconds, keys: false)
            until_at = monotonic + seconds
            cans = 0
            loop do
              left = until_at - monotonic
              return nil if left <= 0

              byte = read(left)
              return nil if byte == :timeout
              return byte if [SOH, STX, EOT].include?(byte)

              cans = cancel_count(byte, cans, keys)
            end
          end

          # The CANs in a row with +byte+; raises Cancelled at CANCEL_COUNT, or
          # at Esc or Ctrl-C with +keys+.
          def cancel_count(byte, cans, keys)
            raise Cancelled if keys && CANCEL_KEYS.include?(byte)

            cans = byte == CAN ? cans + 1 : 0
            raise Cancelled if cans >= CANCEL_COUNT

            cans
          end

          # Reads the block that +head+ starts and keeps it, acknowledged, when
          # it is the next one.
          def take(head, data, max_bytes)
            number, chunk = block(head)
            return refuse(Failed) unless chunk
            return emit(ACK.chr) if number == ((@next - 1) & BYTE_MASK)
            raise Failed unless number == (@next & BYTE_MASK)
            raise TooLarge if data.bytesize + chunk.bytesize > max_bytes

            data << chunk
            @next  += 1
            @errors = 0
            emit(ACK.chr)
          end

          # Asks for the block again with a NAK after the line goes quiet;
          # raises +error+ after TRIES in a row.
          def refuse(error)
            @errors += 1
            raise error if @errors >= TRIES

            quiet(PURGE_QUIET, BLOCK_WAIT)
            emit(NAK.chr)
          end
        end
      end
    end
  end
end
