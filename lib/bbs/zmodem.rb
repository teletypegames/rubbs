# frozen_string_literal: true

require 'zlib'

module BBS
  # ZMODEM downloads: the sending side of Chuck Forsberg's protocol, enough
  # for the caller's terminal to save files from the BBS — SyncTERM,
  # NetRunner, Qodem, lrzsz's `rz` behind a plain telnet, or zmodem.js in a
  # web terminal.
  #
  #   BBS::Zmodem.send_files(session, [['README.TXT', bytes, Time.now]])
  #   # => :ok, :cancelled, :timeout or :hangup
  #
  # Every control character goes out ZDLE-escaped, so the stream holds no
  # bare CR and needs no telnet BINARY mode, and 0xFF goes out as a doubled
  # telnet IAC (`telnet: false` for a plain byte pipe). While it waits for
  # the terminal to answer, Esc or Ctrl-C gives up.
  module Zmodem
    ZPAD   = 0x2a
    ZDLE   = 0x18
    ZBIN   = 0x41
    ZHEX   = 0x42
    ZBIN32 = 0x43
    XON    = 0x11

    ZRQINIT = 0
    ZRINIT  = 1
    ZACK    = 3
    ZFILE   = 4
    ZSKIP   = 5
    ZNAK    = 6
    ZABORT  = 7
    ZFIN    = 8
    ZRPOS   = 9
    ZDATA   = 10
    ZEOF    = 11
    ZFERR   = 12
    ZCRC    = 13
    ZCAN    = 16

    ZCRCE = 0x68
    ZCRCG = 0x69
    ZCRCW = 0x6b

    CANFC32 = 0x20
    ZCBIN   = 1

    SUBPACKET = 1024
    ABORT     = ("\x18" * 8 + "\b" * 8).b

    Header = Struct.new(:type, :bytes) do
      def position = bytes.each_with_index.sum { |b, i| b << (8 * i) }
      def flags    = bytes[3]
    end

    class Cancelled < StandardError; end
    class Timeout < StandardError; end
    class Hangup < StandardError; end

    module_function

    # Sends `files`, an Array of [name, data] or [name, data, mtime], and
    # returns :ok when the terminal took them (or skipped some), :cancelled
    # when the caller or the terminal gave up, :timeout when no ZMODEM
    # receiver answered within `wait` seconds, :hangup when the line dropped.
    def send_files(session, files, wait: 30, telnet: true)
      Sender.new(session, telnet: telnet).run(files, wait: wait)
    end

    def crc16(bytes, crc = 0)
      bytes.each_byte do |b|
        crc ^= b << 8
        8.times { crc = crc.anybits?(0x8000) ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff }
      end
      crc
    end

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

    class Sender
      def initialize(session, telnet: true)
        @session = session
        @telnet  = telnet
        @pending = []
        @cans    = 0
      end

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
