# frozen_string_literal: true

module BBS
  module Zmodem
    # Headers read out of the receiver's bytes: hex headers and binary ones
    # with a CRC-16 or a CRC-32, ZDLE escapes undone, the CRC checked.
    module Frames
      module_function

      # Parses the header at the start of +buf+ (an Array of byte Integers
      # beginning with ZPAD). Returns <tt>[header, used]</tt>: the Header
      # (+nil+ for a broken one) and the bytes it took, or <tt>[nil, nil]</tt>
      # when +buf+ ends before the header does.
      def parse(buf)
        i = 0
        i += 1 while buf[i] == ZPAD
        return [nil, nil] if i == buf.size
        return [nil, i] unless buf[i] == ZDLE
        return [nil, nil] if i + 1 >= buf.size

        parse_frame(buf, buf[i + 1], i + 2)
      end

      # The header of kind +kind+ (ZHEX, ZBIN, ZBIN32) whose bytes start at
      # +from+; see #parse.
      def parse_frame(buf, kind, from)
        case kind
        when ZHEX   then parse_hex(buf, from)
        when ZBIN   then parse_bin(buf, from, CRC16_SIZE)
        when ZBIN32 then parse_bin(buf, from, CRC32_SIZE)
        else [nil, from - 1]
        end
      end

      # A hex header from +from+; see #parse.
      def parse_hex(buf, from)
        to = from + HEX_DIGITS
        return [nil, nil] if buf.size < to

        text = buf[from, HEX_DIGITS].pack('C*')
        return [nil, from] unless text.match?(HEX_HEADER_RE)

        bytes = [text].pack('H*').bytes
        [(header_of(bytes) if crc_ok?(bytes, CRC16_SIZE)), to]
      end

      # A binary header from +from+ with a CRC of +crc_size+ bytes; see
      # #parse.
      def parse_bin(buf, from, crc_size)
        bytes, used = unescape(buf, from, HEADER_SIZE + crc_size)
        return [nil, nil] unless bytes

        [(header_of(bytes) if crc_ok?(bytes, crc_size)), used]
      end

      # The +count+ bytes from +from+ with the ZDLE escapes undone, and where
      # they end; +nil+ when +buf+ ends first.
      def unescape(buf, from, count)
        bytes = []
        while bytes.size < count
          step = buf[from] == ZDLE ? 2 : 1
          return if from + step > buf.size

          bytes << (step == 2 ? ZDLE_VALUES.fetch(buf[from + 1]) { |c| c ^ ZDLE_XOR } : buf[from])
          from += step
        end
        [bytes, from]
      end

      # Whether the CRC of +crc_size+ bytes after the header in +bytes+ is
      # right.
      def crc_ok?(bytes, crc_size)
        frame = bytes[0, HEADER_SIZE].pack('C*')
        crc   = bytes[HEADER_SIZE, crc_size]
        return Zlib.crc32(frame) == crc.pack('C*').unpack1('V') if crc_size == CRC32_SIZE

        Zmodem.crc16(frame) == ((crc[0] << 8) | crc[1])
      end

      # The Header of the first HEADER_SIZE +bytes+.
      def header_of(bytes) = Header.new(bytes[0], bytes[1, 4])
    end
  end
end
