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
    ABORT     = ((ZDLE.chr * 8) + (Ascii::BS.chr * 8)).b

    # The command that starts the receiver on a Unix shell: +rz+ and CR.
    RZ_COMMAND   = "rz#{Ansi::CR}".b.freeze
    # What starts a hex header: two ZPAD, ZDLE and ZHEX.
    HEX_HEADER   = [ZPAD, ZPAD, ZDLE, ZHEX].pack('C*').freeze
    # What starts a binary header, before ZBIN or ZBIN32: ZPAD and ZDLE.
    BIN_HEADER   = [ZPAD, ZDLE].pack('C*').freeze
    # "Over and out", the sender's last word after ZFIN.
    OVER_AND_OUT = 'OO'.b.freeze
    # The Unix file mode sent in the ZFILE header, in octal.
    FILE_MODE    = '100644'
    # The telnet IAC byte, doubled in the data on a telnet line.
    TELNET_IAC   = Telnet::IAC.chr.b.freeze

    # The CRC-16/XMODEM polynomial.
    CRC16_POLY = 0x1021
    # The top bit of a CRC-16, shifted out before the polynomial is added.
    CRC16_TOP  = 0x8000
    # The bits of a CRC-16.
    CRC16_MASK = 0xffff
    # The bytes of a CRC-16 after a header or subpacket.
    CRC16_SIZE = 2
    # The bytes of a CRC-32 after a header or subpacket.
    CRC32_SIZE = 4
    # The C0 control bytes, sent escaped.
    ESCAPED_C0 = 0x00..0x1f
    # The C1 control bytes, sent escaped.
    ESCAPED_C1 = 0x80..0x9f
    # XORed into an escaped byte after ZDLE.
    ZDLE_XOR   = 0x40
    # ZRUB0: ZDLE and this byte stand for ZRUB0_VALUE.
    ZRUB0      = 0x6c
    # The byte ZRUB0 stands for: DEL.
    ZRUB0_VALUE = 0x7f
    # ZRUB1: ZDLE and this byte stand for ZRUB1_VALUE.
    ZRUB1 = 0x6d
    # The byte ZRUB1 stands for.
    ZRUB1_VALUE = 0xff
    # The bytes of a header before its CRC: the type and four data bytes.
    HEADER_SIZE = 5
    # The hex digits of a hex header after ZHEX: type, data and CRC-16.
    HEX_DIGITS  = 14
    # A hex header's digits.
    HEX_HEADER_RE = /\A\h{14}\z/

    # The keys the caller cancels the start of a transfer with: Esc and
    # Ctrl-C.
    CANCEL_KEYS  = [Ascii::ESC, Ascii::ETX].freeze
    # The ZDLE (CAN) bytes in a row that cancel the transfer.
    CANCEL_COUNT = 5
    # Times a ZFILE header is sent before the file is given up.
    FILE_TRIES   = 5
    # Seconds to wait for the receiver's answer, by default.
    WAIT         = 30
    # Seconds to wait for one answer to ZRQINIT or ZFILE.
    ANSWER_WAIT  = 10
    # Seconds to wait for the receiver's ZFIN.
    FIN_WAIT     = 5
    # The most times a file is sent again from where the receiver asks
    # (ZRPOS) before the transfer is given up.
    RESTARTS     = 16
    # The most bytes of a file sent, counting the restarts, as a multiple of
    # its size (or of SUBPACKET for a smaller file); past it the transfer is
    # given up.
    BUDGET_FACTOR = 4
    # The most bytes of the receiver kept while looking for a header; older
    # ones are dropped.
    MAX_PENDING = 64

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
    # +:cancelled+ when the caller or the terminal gave up (or the terminal
    # asked for a file again more than RESTARTS times or for more than
    # BUDGET_FACTOR times its bytes), +:timeout+ when
    # no receiver answered within +wait+ seconds, +:hangup+ when the line
    # dropped.
    def send_files(session, files, wait: WAIT, telnet: true)
      Sender.new(session, telnet: telnet).run(files, wait: wait)
    end

    # Returns the CRC-16/XMODEM (polynomial 0x1021) of the String +bytes+,
    # continuing from +crc+.
    def crc16(bytes, crc = 0)
      bytes.each_byte do |b|
        crc ^= b << 8
        8.times { crc = crc.anybits?(CRC16_TOP) ? ((crc << 1) ^ CRC16_POLY) & CRC16_MASK : (crc << 1) & CRC16_MASK }
      end
      crc
    end

    # Returns a binary copy of +bytes+ with every C0 and C1 control byte
    # (0x00-0x1f, 0x80-0x9f) replaced by ZDLE and the byte XOR 0x40.
    def escape(bytes)
      out = +''.b
      bytes.each_byte do |b|
        case b
        when ESCAPED_C0, ESCAPED_C1 then out << ZDLE << (b ^ ZDLE_XOR)
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
        emit(RZ_COMMAND)
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
          header = read_header(timeout: [ANSWER_WAIT, deadline - monotonic].min, interruptible: true)
          if header&.type == ZRINIT
            @crc32 = header.flags.to_i.anybits?(CANFC32)
            @window = header.bytes[0] | (header.bytes[1] << 8)
            return
          end
          raise Timeout if monotonic >= deadline
        end
      end

      def send_file(name, data, mtime, rest)
        info = "#{name}#{Ascii::NUL_CHAR}#{data.bytesize} #{mtime.to_i.to_s(8)} #{FILE_MODE} 0 #{rest.size} " \
               "#{rest.sum { |f| f[1].bytesize }}#{Ascii::NUL_CHAR}".b
        FILE_TRIES.times do
          bin_header(ZFILE, [0, 0, 0, ZCBIN])
          subpacket(info, ZCRCW)
          header = expect(ZRPOS, ZSKIP, ZCRC, ZNAK, timeout: ANSWER_WAIT, ignore_timeout: true)
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

      # Sends +data+ from +pos+ and its end, again from where the receiver
      # asks, at most RESTARTS times and BUDGET_FACTOR times its size.
      def stream(data, pos)
        @budget = BUDGET_FACTOR * [data.bytesize, SUBPACKET].max
        RESTARTS.times do
          pos = send_data(data, pos) || end_of_file(data, pos)
          return if pos == :done
        end
        raise Cancelled
      end

      # :done when the receiver took the file, else where to send from.
      def end_of_file(data, pos)
        bin_header(ZEOF, position_bytes(data.bytesize))
        header = expect(ZRINIT, ZRPOS, ZNAK)
        case header.type
        when ZRINIT then :done
        when ZRPOS  then header.position
        else pos
        end
      end

      # The subpackets from +pos+ to the end: nil when all went out, the
      # position the receiver asked for (ZRPOS) when it wants them again.
      def send_data(data, pos)
        pos = pos.clamp(0, data.bytesize)
        return if pos == data.bytesize

        start = pos
        bin_header(ZDATA, position_bytes(pos))
        acked = pos
        while pos < data.bytesize
          chunk = spend(data.byteslice(pos, SUBPACKET))
          pos  += chunk.bytesize
          last  = pos >= data.bytesize
          if @window.positive? && pos - acked >= @window && !last
            subpacket(chunk, ZCRCW)
            header = expect(ZACK, ZRPOS)
            return header.position if header.type == ZRPOS

            acked = pos
          else
            subpacket(chunk, last ? ZCRCE : ZCRCG)
          end
          header = poll_header
          return header.position if header&.type == ZRPOS && header.position != start
        end
        nil
      end

      def spend(chunk)
        @budget -= chunk.bytesize
        raise Cancelled if @budget.negative?

        chunk
      end

      def finish
        hex_header(ZFIN, [0, 0, 0, 0])
        read_header(timeout: FIN_WAIT)
        emit(OVER_AND_OUT)
      end

      def position_bytes(pos) = [pos].pack('V').bytes

      def hex_header(type, bytes)
        frame = [type, *bytes].pack('C*')
        crc = Zmodem.crc16(frame)
        hex = (frame + [crc].pack('n')).unpack1('H*')
        tail = [ZFIN, ZACK].include?(type) ? '' : XON.chr
        emit("#{HEX_HEADER}#{hex}#{Ansi::CRLF}#{tail}".b)
      end

      def bin_header(type, bytes)
        frame = [type, *bytes].pack('C*')
        out = +BIN_HEADER
        if @crc32
          out << ZBIN32 << Zmodem.escape(frame + [Zlib.crc32(frame)].pack('V'))
        else
          out << ZBIN << Zmodem.escape(frame + [Zmodem.crc16(frame)].pack('n'))
        end
        emit(out)
      end

      def subpacket(data, frameend)
        out = Zmodem.escape(data) << ZDLE << frameend
        out << if @crc32
                 Zmodem.escape([Zlib.crc32(data + frameend.chr)].pack('V'))
               else
                 Zmodem.escape([Zmodem.crc16(data + frameend.chr)].pack('n'))
               end
        out << XON if frameend == ZCRCW
        emit(out)
      end

      def expect(*types, timeout: WAIT, ignore_timeout: false)
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
          raise Cancelled if interruptible && CANCEL_KEYS.include?(byte)

          push(byte)
        end
      end

      def push(byte)
        @cans = byte == ZDLE ? @cans + 1 : 0
        raise Cancelled if @cans >= CANCEL_COUNT

        @pending << byte
        @pending.shift(@pending.size - MAX_PENDING) if @pending.size > MAX_PENDING
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
        when ZBIN   then parse_bin(buf, i + 2, CRC16_SIZE)
        when ZBIN32 then parse_bin(buf, i + 2, CRC32_SIZE)
        else [nil, i + 1]
        end
      end

      def parse_hex(buf, from)
        return [nil, nil] if buf.size < from + HEX_DIGITS

        text = buf[from, HEX_DIGITS].pack('C*')
        return [nil, from] unless text.match?(HEX_HEADER_RE)

        bytes = [text].pack('H*').bytes
        crc   = (bytes[HEADER_SIZE] << 8) | bytes[HEADER_SIZE + 1]
        return [nil, from + HEX_DIGITS] unless Zmodem.crc16(bytes[0, HEADER_SIZE].pack('C*')) == crc

        [Header.new(bytes[0], bytes[1, 4]), from + HEX_DIGITS]
      end

      def parse_bin(buf, from, crc_size)
        bytes = []
        i = from
        while bytes.size < HEADER_SIZE + crc_size
          return [nil, nil] if i >= buf.size

          if buf[i] == ZDLE
            return [nil, nil] if i + 1 >= buf.size

            c = buf[i + 1]
            bytes << (if c == ZRUB0
                        ZRUB0_VALUE
                      else
                        c == ZRUB1 ? ZRUB1_VALUE : c ^ ZDLE_XOR
                      end)
            i += 2
          else
            bytes << buf[i]
            i += 1
          end
        end
        frame = bytes[0, HEADER_SIZE].pack('C*')
        crc   = bytes[HEADER_SIZE, crc_size]
        ok = if crc_size == CRC32_SIZE
               Zlib.crc32(frame) == crc.pack('C*').unpack1('V')
             else
               Zmodem.crc16(frame) == ((crc[0] << 8) | crc[1])
             end
        ok ? [Header.new(bytes[0], bytes[1, 4]), i] : [nil, i]
      end

      def emit(bytes)
        @session.write_raw(@telnet ? bytes.b.gsub(TELNET_IAC, TELNET_IAC * 2) : bytes)
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
