# frozen_string_literal: true

module BBS
  # XMODEM downloads: the sending side of Ward Christensen's protocol and
  # its CRC and 1K variants, the transfer the terminals of a Commodore 64
  # (CCGMS, Novaterm, UltimateTerm and the like) know besides SyncTERM,
  # Qodem and lrzsz's +rx+.
  #
  #   BBS::Xmodem.send_file(session, bytes)
  #   BBS::Xmodem.send_file(session, bytes, one_k: true)
  #   # => :ok, :cancelled, :timeout or :hangup
  #
  # XMODEM carries no file name: the caller names the file in the terminal
  # before the transfer starts. The last block is padded with SUB (0x1a)
  # up to its size, so the received file may be longer than the original.
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
    CANCEL_KEYS  = [Ascii::ESC, Ascii::ETX].freeze
    # The CAN bytes in a row from the receiver that cancel the transfer.
    CANCEL_COUNT = 2
    # What the sender writes to cancel: eight CAN, then eight backspaces to
    # erase their echo.
    ABORT = ([CAN] * 8 + [Ascii::BS] * 8).pack('C*').freeze

    # Seconds to wait for the receiver to start, by default.
    WAIT        = 60
    # Seconds to wait for the answer to one block.
    BLOCK_WAIT  = 20
    # Times a block (or the EOT) is sent before the transfer is given up.
    TRIES       = 10
    # Seconds of silence that end the transfer: what the terminal still
    # sends before it (a late +C+, NAK or CAN) is dropped, so the board does
    # not read it as keys.
    QUIET       = 0.5
    # The most seconds spent dropping the terminal's late bytes.
    QUIET_MAX   = 5

    # The telnet IAC byte, doubled in the data on a telnet line.
    TELNET_IAC = Telnet::IAC.chr.b.freeze
    # Asks the terminal for telnet BINARY mode both ways.
    BINARY_ON  = [Telnet::IAC, Telnet::WILL, Telnet::BINARY_OPT,
                  Telnet::IAC, Telnet::DO, Telnet::BINARY_OPT].pack('C*').freeze
    # Leaves telnet BINARY mode both ways.
    BINARY_OFF = [Telnet::IAC, Telnet::WONT, Telnet::BINARY_OPT,
                  Telnet::IAC, Telnet::DONT, Telnet::BINARY_OPT].pack('C*').freeze

    # Raised inside the sender when the caller or the terminal cancels.
    class Cancelled < StandardError; end
    # Raised inside the sender when the terminal does not answer in time.
    class Timeout < StandardError; end
    # Raised inside the sender when the line drops.
    class Hangup < StandardError; end

    module_function

    # Sends +data+ (a String of bytes) to the caller's terminal over
    # +session+.
    #
    # [session] the BBS::Session to send on
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

    # One XMODEM send over a session. Xmodem.send_file is the usual way in.
    class Sender
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
        crc = handshake(wait)
        size = crc && one_k ? BLOCK_1K : BLOCK
        Xmodem.blocks(data, size).each.with_index(1) do |chunk, number|
          deliver(Xmodem.frame(number % BLOCK_NUMBERS, chunk, crc: crc))
        end
        deliver(EOT.chr)
      rescue Cancelled
        emit(ABORT)
        quiet ? :cancelled : :hangup
      rescue Timeout
        emit(ABORT)
        quiet ? :timeout : :hangup
      rescue Hangup, IOError, SystemCallError
        :hangup
      else
        quiet ? :ok : :hangup
      ensure
        @session.write_raw(BINARY_OFF) if @telnet
      end

      private

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

      # Drops bytes until QUIET seconds pass without one; false on hangup.
      def quiet
        deadline = monotonic + QUIET_MAX
        while monotonic < deadline
          byte = @session.read_raw_byte(QUIET)
          return false if byte.nil?
          return true if byte == :timeout
        end
        true
      rescue IOError, SystemCallError
        false
      end

      def emit(bytes)
        @session.write_raw(@telnet ? bytes.b.gsub(TELNET_IAC, TELNET_IAC * 2) : bytes)
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
