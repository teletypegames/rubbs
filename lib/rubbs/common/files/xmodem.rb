# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      # XMODEM both ways: Ward Christensen's protocol and its CRC and 1K
      # variants, the transfer the terminals of a Commodore 64 (CCGMS,
      # Novaterm, UltimateTerm and the like) know besides SyncTERM, Qodem and
      # lrzsz's +sx+ and +rx+. Downloads go out by Sender, uploads come in by
      # Receiver.
      #
      #   Rubbs::Common::Files::Xmodem.send_file(session, bytes)
      #   Rubbs::Common::Files::Xmodem.send_file(session, bytes, one_k: true)
      #   # => :ok, :cancelled, :timeout or :hangup
      #
      #   Rubbs::Common::Files::Xmodem.receive_file(session, max_bytes: 8192)
      #   # => the bytes, or :cancelled, :timeout, :too_large, :failed or :hangup
      #
      # XMODEM carries no file name: the caller names the file in the terminal
      # before the transfer starts. The last block is padded (with SUB, 0x1a,
      # by most senders) up to its size, so the received file may be longer
      # than the original: a receiver gets the padding too.
      #
      # The bytes go out as they are, past the PETSCII encoder, with 0xFF as a
      # doubled telnet IAC (<tt>telnet: false</tt> for a plain byte pipe), and
      # the line is asked into telnet BINARY mode for the transfer.
      module Xmodem
        # Start of a 128-byte block.
        SOH = 0x01
        # Start of a 1024-byte block (XMODEM-1K).
        STX = 0x02
        # End of transmission: the sender has no more blocks.
        EOT = 0x04
        # The receiver took the block.
        ACK = 0x06
        # The receiver wants the block again; as the first byte, it asks for a
        # transfer with an arithmetic checksum.
        NAK = 0x15
        # Cancel: two in a row end the transfer.
        CAN = 0x18
        # The padding byte of the last block (Ctrl-Z).
        SUB = 0x1a
        # The receiver's first byte when it wants a CRC-16 instead of a checksum.
        CRC_START = 'C'.ord

        # The data bytes of a classic block.
        BLOCK = 128
        # The data bytes of an XMODEM-1K block.
        BLOCK_1K = 1024
        # The block numbers count modulo this.
        BLOCK_NUMBERS = 256
        # The largest byte, for the ones' complement of a block number and the
        # checksum.
        BYTE_MASK = 0xff

        # The keys the caller cancels the start of a transfer with: Esc and
        # Ctrl-C (RUN/STOP on a Commodore 64).
        CANCEL_KEYS  = [Line::Ascii::ESC, Line::Ascii::ETX].freeze
        # The CAN bytes in a row from the receiver that cancel the transfer.
        CANCEL_COUNT = 2
        # What the sender writes to cancel: eight CAN, then eight backspaces to
        # erase their echo.
        ABORT = (([CAN] * 8) + ([Line::Ascii::BS] * 8)).pack('C*').freeze

        # Seconds to wait for the receiver to start, by default.
        WAIT        = 60
        # Seconds to wait for the answer to one block (sending), or for the
        # next block (receiving).
        BLOCK_WAIT  = 20
        # Times a block (or the EOT) is sent, or asked for again, before the
        # transfer is given up.
        TRIES       = 10
        # Seconds of silence that end the transfer: what the terminal still
        # sends before it (a late +C+, NAK or CAN) is dropped, so the board does
        # not read it as keys.
        QUIET       = 0.5
        # The most seconds spent dropping the terminal's late bytes.
        QUIET_MAX   = 5

        # The telnet IAC byte, doubled in the data on a telnet line.
        TELNET_IAC = Line::Telnet::IAC.chr.b.freeze
        # Asks the terminal for telnet BINARY mode both ways.
        BINARY_ON  = [Line::Telnet::IAC, Line::Telnet::WILL, Line::Telnet::BINARY_OPT, Line::Telnet::IAC, Line::Telnet::DO, Line::Telnet::BINARY_OPT].pack('C*').freeze
        # Leaves telnet BINARY mode both ways.
        BINARY_OFF = [Line::Telnet::IAC, Line::Telnet::WONT, Line::Telnet::BINARY_OPT, Line::Telnet::IAC, Line::Telnet::DONT, Line::Telnet::BINARY_OPT].pack('C*').freeze

        # The most bytes a receive takes by default.
        MAX_RECEIVE = 1024 * 1024
        # Seconds a receive may take from its first block to its end, by
        # default.
        LIMIT = 300

        # Raised inside a transfer when the caller or the terminal cancels.
        class Cancelled < StandardError; end
        # Raised inside a transfer when the terminal does not answer in time.
        class Timeout < StandardError; end
        # Raised inside a transfer when the line drops.
        class Hangup < StandardError; end
        # Raised inside a receive when the file grows past its +max_bytes+.
        class TooLarge < StandardError; end
        # Raised inside a receive when the blocks keep coming wrong or out of
        # order.
        class Failed < StandardError; end

        module_function

        # Sends +data+ (a String of bytes) to the caller's terminal over
        # +session+.
        #
        # [session] the Rubbs::Common::Line::Session to send on
        # [data]    the file's bytes
        # [one_k]   1024-byte blocks (XMODEM-1K) when the receiver asked for a
        #           CRC; +false+ sends 128-byte blocks
        # [wait]    seconds to wait for the receiver to start
        # [telnet]  double 0xFF bytes as telnet IAC and ask for BINARY mode;
        #           +false+ for a plain byte pipe
        #
        # The receiver picks the check: a +C+ gets CRC-16, a NAK the arithmetic
        # checksum (and 128-byte blocks, even with +one_k+). Esc or Ctrl-C from
        # the caller gives up while the board waits for the start.
        #
        # Returns +:ok+ when the terminal acknowledged the end of the file,
        # +:cancelled+ when the caller or the terminal gave up, +:timeout+ when
        # the receiver did not start within +wait+ seconds or stopped
        # answering, +:hangup+ when the line dropped.
        def send_file(session, data, one_k: false, wait: WAIT, telnet: true)
          Sender.new(session, telnet: telnet).run(data.to_s.b, one_k: one_k, wait: wait)
        end

        # Receives a file the caller's terminal uploads over +session+.
        #
        # [session]   the Rubbs::Common::Line::Session to receive on
        # [max_bytes] the most bytes taken: a longer file is cancelled
        # [wait]      seconds to wait for the terminal to start sending
        # [limit]     seconds the transfer may take from its first block on
        # [telnet]    take a doubled 0xFF as one byte and ask for BINARY mode;
        #             +false+ for a plain byte pipe
        #
        # The board asks for a CRC-16 (+C+) first and for the arithmetic
        # checksum (NAK) after a while, for the senders that know only that;
        # the first block tells which one the sender uses. 128-byte and
        # 1024-byte (XMODEM-1K) blocks are both taken. Esc or Ctrl-C (RUN/STOP)
        # from the caller gives up while the board waits for the start.
        #
        # Returns the received bytes (a binary String, the padding of the last
        # block included) when the terminal ended the file, +:cancelled+ when
        # the caller or the terminal gave up, +:timeout+ when the terminal did
        # not start within +wait+ seconds, stopped sending or went past
        # +limit+, +:too_large+ when the file grew past +max_bytes+, +:failed+
        # when the blocks kept coming broken or out of order, +:hangup+ when
        # the line dropped.
        def receive_file(session, max_bytes: MAX_RECEIVE, wait: WAIT, limit: LIMIT, telnet: true)
          Receiver.new(session, telnet: telnet).run(max_bytes: max_bytes, wait: wait, limit: limit)
        end

        # Returns the arithmetic checksum of the String +bytes+: the sum of the
        # bytes modulo 256.
        def checksum(bytes) = bytes.sum & BYTE_MASK

        # Cuts +data+ into the blocks of a transfer: Strings of +size+ bytes,
        # the last one padded with SUB. An empty +data+ gives no blocks.
        def blocks(data, size)
          (0...data.bytesize).step(size).map do |pos|
            data.byteslice(pos, size).ljust(size, SUB.chr)
          end
        end

        # Returns one block on the line, before telnet escaping: the start byte
        # (SOH or STX by the size of +chunk+), block number +number+ and its
        # ones' complement, +chunk+, then the CRC-16 (big-endian) when +crc+ is
        # true, else the checksum.
        def frame(number, chunk, crc:)
          number &= BYTE_MASK
          head = [chunk.bytesize == BLOCK_1K ? STX : SOH, number, BYTE_MASK - number].pack('C*')
          tail = crc ? [Zmodem.crc16(chunk)].pack('n') : [checksum(chunk)].pack('C')
          head + chunk + tail
        end
      end
    end
  end
end

require_relative 'xmodem/wire'
require_relative 'xmodem/sender'
require_relative 'xmodem/block_reader'
require_relative 'xmodem/receiver'
