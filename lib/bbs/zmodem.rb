# frozen_string_literal: true

require 'zlib'

module BBS
  # ZMODEM downloads: the sending side of Chuck Forsberg's protocol, enough
  # for the caller's terminal to save files from the BBS: SyncTERM,
  # NetRunner, Qodem, lrzsz's +rz+ behind a plain telnet, or zmodem.js in a
  # web terminal.
  #
  #   BBS::Zmodem.send_files(session, [['README.TXT', bytes, Time.now]])
  #   # => :ok, :cancelled, :timeout or :hangup
  #
  # Every control character goes out ZDLE-escaped, so the stream holds no
  # bare CR and needs no telnet BINARY mode, and 0xFF goes out as a doubled
  # telnet IAC (<tt>telnet: false</tt> for a plain byte pipe). While it waits
  # for the terminal to answer, Esc or Ctrl-C gives up.
  module Zmodem
    # Frame padding character (<tt>*</tt>) that starts every header.
    ZPAD   = 0x2a
    # ZMODEM data link escape (Ctrl-X): prefixes escaped bytes and header
    # formats; five in a row cancel the transfer.
    ZDLE   = 0x18
    # Header format byte: binary header with a CRC-16.
    ZBIN   = 0x41
    # Header format byte: hex header with a CRC-16.
    ZHEX   = 0x42
    # Header format byte: binary header with a CRC-32.
    ZBIN32 = 0x43
    # XON (Ctrl-Q), sent after hex headers and ZCRCW subpackets to restart
    # a receiver that uses software flow control.
    XON    = 0x11

    # Header type: sender asks the receiver to send ZRINIT.
    ZRQINIT = 0
    # Header type: receiver is ready; carries its buffer size and
    # capability flags.
    ZRINIT  = 1
    # Header type: acknowledges a ZCRCW subpacket.
    ZACK    = 3
    # Header type: file name and size follow in a subpacket.
    ZFILE   = 4
    # Header type: receiver skips the offered file.
    ZSKIP   = 5
    # Header type: last header was garbled, send it again.
    ZNAK    = 6
    # Header type: receiver aborts the batch.
    ZABORT  = 7
    # Header type: end of the session.
    ZFIN    = 8
    # Header type: receiver asks for data from the given file position.
    ZRPOS   = 9
    # Header type: data subpackets follow from the given position.
    ZDATA   = 10
    # Header type: end of file at the given position.
    ZEOF    = 11
    # Header type: receiver hit a fatal file error.
    ZFERR   = 12
    # Header type: request for, or answer with, the file's CRC-32.
    ZCRC    = 13
    # Header type: the other side cancelled the transfer.
    ZCAN    = 16

    # Subpacket end: CRC follows, frame ends, no answer expected.
    ZCRCE = 0x68
    # Subpacket end: CRC follows, more data comes without waiting.
    ZCRCG = 0x69
    # Subpacket end: CRC follows, the receiver must answer with ZACK.
    ZCRCW = 0x6b

    # ZRINIT capability flag: the receiver understands CRC-32 frames.
    CANFC32 = 0x20
    # ZFILE conversion option: binary transfer, no line-end conversion.
    ZCBIN   = 1

    # Bytes of file data per data subpacket.
    SUBPACKET = 1024
    # The abort sequence: eight Ctrl-X followed by eight backspaces, which
    # makes the receiver drop the transfer and erases the echo.
    ABORT     = ("\x18" * 8 + "\b" * 8).b

    # A parsed ZMODEM header: +type+ is the header type (ZRINIT, ZRPOS, ...),
    # +bytes+ the four data bytes. #position reads them as a little-endian
    # file offset, #flags returns the fourth byte (ZF0).
    Header = Struct.new(:type, :bytes) do
      def position = bytes.each_with_index.sum { |b, i| b << (8 * i) }
      def flags    = bytes[3]
    end

    # Raised inside the sender when the caller or the terminal cancels.
    class Cancelled < StandardError; end
    # Raised inside the sender when the terminal does not answer in time.
    class Timeout < StandardError; end
    # Raised inside the sender when the line drops.
    class Hangup < StandardError; end

    module_function

    # Sends +files+ to the caller's terminal over +session+.
    #
    # [session] the BBS::Session to send on
    # [files]   an Array of <tt>[name, data]</tt> or <tt>[name, data, mtime]</tt>;
    #           only the base name of +name+ is sent, +mtime+ defaults to now
    # [wait]    seconds to wait for a ZMODEM receiver to answer
    # [telnet]  double 0xFF bytes as telnet IAC; +false+ for a plain byte pipe
    #
    # Returns +:ok+ when the terminal took the files (or skipped some),
    # +:cancelled+ when the caller or the terminal gave up, +:timeout+ when
    # no receiver answered within +wait+ seconds, +:hangup+ when the line
    # dropped.
    def send_files(session, files, wait: 30, telnet: true)
      Sender.new(session, telnet: telnet).run(files, wait: wait)
    end

    # Returns the CRC-16/XMODEM (polynomial 0x1021) of the String +bytes+,
    # continuing from +crc+.
    def crc16(bytes, crc = 0)
      bytes.each_byte do |b|
        crc ^= b << 8
        8.times { crc = crc.anybits?(0x8000) ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff }
      end
      crc
    end

    # Returns a binary copy of +bytes+ with every C0 and C1 control byte
    # (0x00-0x1f, 0x80-0x9f) replaced by ZDLE and the byte XOR 0x40.
    def escape(bytes)
      out = +''.b
      bytes.each_byte do |b|
        case b
        when 0x00..0x1f, 0x80..0x9f then out << ZDLE << (b ^ 0x40)
        else out << b
        end
      end
      out
    end

    # One ZMODEM batch send over a session. Zmodem.send_files is the usual
    # way in.
    class Sender
      # Creates a sender writing to and reading raw bytes from +session+;
      # +telnet+ doubles 0xFF bytes as telnet IAC.
      def initialize(session, telnet: true)
        @session = session
        @telnet  = telnet
        @pending = []
        @cans    = 0
      end

      # Sends +files+ (as for Zmodem.send_files): writes +rz+ and CR, waits
      # up to +wait+ seconds for ZRINIT, offers and streams each file, then
      # ends the session with ZFIN. Writes the abort sequence on cancel or
      # timeout.
      #
      # Returns +:ok+, +:cancelled+, +:timeout+ or +:hangup+.
      def run(files, wait:)
        files = files.map { |name, data, mtime| [File.basename(name.to_s), data.to_s.b, mtime || Time.now] }
        emit("rz\r".b)
        handshake(wait)
        files.each_with_index { |file, i| send_file(*file, files[i..]) }
        finish
        :ok
      rescue Cancelled
        emit(ABORT)
        :cancelled
      rescue Timeout
        emit(ABORT)
        :timeout
      rescue Hangup, IOError, SystemCallError
        :hangup
      end

      private

      def handshake(wait)
        deadline = monotonic + wait
        loop do
          hex_header(ZRQINIT, [0, 0, 0, 0])
          header = read_header(timeout: [10, deadline - monotonic].min, interruptible: true)
          if header&.type == ZRINIT
            @crc32 = header.flags.to_i.anybits?(CANFC32)
            @window = header.bytes[0] | (header.bytes[1] << 8)
            return
          end
          raise Timeout if monotonic >= deadline
        end
      end

      def send_file(name, data, mtime, rest)
        info = "#{name}\0#{data.bytesize} #{mtime.to_i.to_s(8)} 100644 0 #{rest.size} #{rest.sum { |f| f[1].bytesize }}\0".b
        5.times do
          bin_header(ZFILE, [0, 0, 0, ZCBIN])
          subpacket(info, ZCRCW)
          header = expect(ZRPOS, ZSKIP, ZCRC, ZNAK, timeout: 10, ignore_timeout: true)
          case header&.type
          when ZSKIP then return
          when ZRPOS then return stream(data, header.position)
          when ZCRC
            hex_header(ZCRC, [Zlib.crc32(data)].pack('V').bytes)
            header = expect(ZRPOS, ZSKIP)
            return header.type == ZRPOS ? stream(data, header.position) : nil
          end
        end
        raise Timeout
      end

      def stream(data, pos)
        loop do
          send_data(data, pos)
          bin_header(ZEOF, position_bytes(data.bytesize))
          header = expect(ZRINIT, ZRPOS, ZNAK)
          case header.type
          when ZRINIT then return
          when ZRPOS then pos = header.position
          end
        end
      end

      def send_data(data, pos)
        pos = pos.clamp(0, data.bytesize)
        return if pos == data.bytesize

        start = pos
        bin_header(ZDATA, position_bytes(pos))
        acked = pos
        while pos < data.bytesize
          chunk = data.byteslice(pos, SUBPACKET)
          pos  += chunk.bytesize
          last  = pos >= data.bytesize
          if @window.positive? && pos - acked >= @window && !last
            subpacket(chunk, ZCRCW)
            header = expect(ZACK, ZRPOS)
            return send_data(data, header.position) if header.type == ZRPOS

            acked = pos
          else
            subpacket(chunk, last ? ZCRCE : ZCRCG)
          end
          header = poll_header
          return send_data(data, header.position) if header&.type == ZRPOS && header.position != start
        end
      end

      def finish
        hex_header(ZFIN, [0, 0, 0, 0])
        read_header(timeout: 5)
        emit('OO'.b)
      end

      def position_bytes(pos) = [pos].pack('V').bytes

      def hex_header(type, bytes)
        frame = [type, *bytes].pack('C*')
        crc = Zmodem.crc16(frame)
        hex = (frame + [crc].pack('n')).unpack1('H*')
        tail = [ZFIN, ZACK].include?(type) ? '' : XON.chr
        emit("**\x18B#{hex}\r\n#{tail}".b)
      end

      def bin_header(type, bytes)
        frame = [type, *bytes].pack('C*')
        out = +"*\x18".b
        if @crc32
          out << ZBIN32 << Zmodem.escape(frame + [Zlib.crc32(frame)].pack('V'))
        else
          out << ZBIN << Zmodem.escape(frame + [Zmodem.crc16(frame)].pack('n'))
        end
        emit(out)
      end

      def subpacket(data, frameend)
        out = Zmodem.escape(data) << ZDLE << frameend
        if @crc32
          out << Zmodem.escape([Zlib.crc32(data + frameend.chr)].pack('V'))
        else
          out << Zmodem.escape([Zmodem.crc16(data + frameend.chr)].pack('n'))
        end
        out << XON if frameend == ZCRCW
        emit(out)
      end

      def expect(*types, timeout: 30, ignore_timeout: false)
        deadline = monotonic + timeout
        loop do
          header = read_header(timeout: deadline - monotonic)
          return nil if header.nil? && ignore_timeout
          raise Timeout if header.nil?
          raise Cancelled if [ZCAN, ZABORT, ZFERR].include?(header.type)
          return header if types.include?(header.type)
        end
      end

      def poll_header
        while (byte = @session.read_raw_byte(0)).is_a?(Integer)
          push(byte)
        end
        raise Hangup if byte.nil?

        scan_pending
      end

      def read_header(timeout:, interruptible: false)
        deadline = monotonic + timeout
        loop do
          header = scan_pending
          return header if header

          left = deadline - monotonic
          return nil if left <= 0

          byte = @session.read_raw_byte(left)
          raise Hangup if byte.nil?
          return nil if byte == :timeout
          raise Cancelled if interruptible && [0x1b, 0x03].include?(byte)

          push(byte)
        end
      end

      def push(byte)
        @cans = byte == ZDLE ? @cans + 1 : 0
        raise Cancelled if @cans >= 5

        @pending << byte
      end

      def scan_pending
        loop do
          start = @pending.index(ZPAD)
          if start.nil?
            @pending.clear
            return nil
          end

          @pending.shift(start)
          header, used = parse(@pending)
          return nil if used.nil?

          @pending.shift(used)
          return header if header
        end
      end

      def parse(buf)
        i = 0
        i += 1 while buf[i] == ZPAD
        return [nil, nil] if i == buf.size
        return [nil, i] unless buf[i] == ZDLE
        return [nil, nil] if i + 1 >= buf.size

        case buf[i + 1]
        when ZHEX   then parse_hex(buf, i + 2)
        when ZBIN   then parse_bin(buf, i + 2, 2)
        when ZBIN32 then parse_bin(buf, i + 2, 4)
        else [nil, i + 1]
        end
      end

      def parse_hex(buf, from)
        return [nil, nil] if buf.size < from + 14

        text = buf[from, 14].pack('C*')
        return [nil, from] unless text.match?(/\A\h{14}\z/)

        bytes = [text].pack('H*').bytes
        return [nil, from + 14] unless Zmodem.crc16(bytes[0, 5].pack('C*')) == (bytes[5] << 8 | bytes[6])

        [Header.new(bytes[0], bytes[1, 4]), from + 14]
      end

      def parse_bin(buf, from, crc_size)
        bytes = []
        i = from
        while bytes.size < 5 + crc_size
          return [nil, nil] if i >= buf.size

          if buf[i] == ZDLE
            return [nil, nil] if i + 1 >= buf.size

            c = buf[i + 1]
            bytes << (c == 0x6c ? 0x7f : c == 0x6d ? 0xff : c ^ 0x40)
            i += 2
          else
            bytes << buf[i]
            i += 1
          end
        end
        frame = bytes[0, 5].pack('C*')
        ok = crc_size == 4 ? Zlib.crc32(frame) == bytes[5, 4].pack('C*').unpack1('V') : Zmodem.crc16(frame) == (bytes[5] << 8 | bytes[6])
        ok ? [Header.new(bytes[0], bytes[1, 4]), i] : [nil, i]
      end

      def emit(bytes)
        @session.write(@telnet ? bytes.b.gsub("\xFF".b, "\xFF\xFF".b) : bytes)
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
