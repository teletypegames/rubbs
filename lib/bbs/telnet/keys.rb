# frozen_string_literal: true

module BBS
  module Telnet
    # Key input of a telnet line: control bytes and UTF-8 characters
    # decoded into Strings and Symbols (#readkey; Telnet::Escapes decodes the
    # escape sequences of the special keys), and raw bytes for binary
    # protocols (#read_raw_byte).
    module Keys
      # Seconds to wait for the rest of an escape sequence (or UTF-8
      # character) before a lone ESC counts as the Escape key.
      ESC_WAIT = 0.15
      # The control bytes Ctrl-A ... Ctrl-Z.
      CTRL_LETTERS = 0x01..0x1a
      # Added to a Ctrl-letter byte, gives its lowercase letter.
      CTRL_TO_LETTER = 0x60
      # The control bytes that are keys of their own; the other Ctrl-letters
      # are <tt>:ctrl_<letter></tt>.
      CONTROL_KEYS = { Ascii::CR => :enter, Ascii::LF => :enter, Ascii::TAB => :tab, Ascii::BS => :backspace,
                       Ascii::DEL => :backspace, Ascii::ETX => :interrupt }.freeze
      # The bytes that start a multibyte UTF-8 character.
      UTF8_LEAD = 0xc2..0xf4
      # The lowest lead byte of a four-byte UTF-8 character.
      UTF8_LEAD_4 = 0xf0
      # The lowest lead byte of a three-byte UTF-8 character.
      UTF8_LEAD_3 = 0xe0
      # The bits that tell a UTF-8 continuation byte.
      UTF8_TAIL_MASK = 0xc0
      # The value of those bits in a continuation byte.
      UTF8_TAIL = 0x80
      # Reads one key press, skipping telnet commands (a NAWS report among
      # them updates the window size). Returns:
      #
      # - a one-character String for a printable character (UTF-8 included),
      # - a Symbol for a special key: +:enter+, +:tab+, +:backspace+,
      #   +:escape+, +:interrupt+ (Ctrl-C), <tt>:ctrl_a</tt> ... <tt>:ctrl_z</tt>,
      #   arrows, +:home+, +:end+, +:page_up+, +:f1+ ... +:f12+ and the like,
      #   with an <tt>alt_</tt>, <tt>shift_</tt>, <tt>ctrl_</tt> or
      #   <tt>ctrl_shift_</tt> prefix for modified keys,
      # - a MouseEvent for a mouse report,
      # - +:idle+ when nothing came within +timeout+ seconds,
      # - +nil+ when the client hung up.
      #
      # On a PETSCII line the keys come from BBS::Petscii.key. CR LF and CR
      # NUL count as one +:enter+. +timeout+ +nil+ waits forever.
      def readkey(timeout: nil)
        loop do
          raw = read_byte(timeout)
          return :idle if raw == :timeout
          return nil if raw.nil?

          key = key_of(raw)
          return key if key
        end
      end

      # Reads one byte of the line as an Integer, for binary protocols
      # (ZMODEM): telnet commands are taken out and a doubled IAC comes back
      # as 255. Returns +:timeout+ when nothing came within +timeout+ seconds
      # and +nil+ on hangup.
      def read_raw_byte(timeout)
        loop do
          raw = read_byte(timeout)
          return raw unless raw.is_a?(String)

          byte = telnet_data(raw.ord)
          return byte if byte
        end
      end

      private

      # The key of the byte String +raw+; +nil+ when it is no key by itself
      # (a telnet command, the LF of a CR LF, a broken character).
      def key_of(raw)
        byte = telnet_data(raw.ord) or return
        return Petscii.key(byte) if @petscii
        return if line_end_pair?(byte)

        ascii_key(byte, raw)
      end

      def ascii_key(byte, raw)
        return CONTROL_KEYS[byte] if CONTROL_KEYS.key?(byte)
        return read_escape_sequence if byte == Ascii::ESC
        return :"ctrl_#{(byte + CTRL_TO_LETTER).chr}" if CTRL_LETTERS.cover?(byte)
        return raw.force_encoding(Encoding::UTF_8) if Ascii::PRINTABLE.cover?(byte)

        read_utf8(raw) if UTF8_LEAD.cover?(byte)
      end

      # Whether +byte+ is the LF or NUL after a CR: CR LF and CR NUL are one
      # Enter, not two.
      def line_end_pair?(byte)
        after_cr  = @after_cr
        @after_cr = byte == Ascii::CR
        after_cr && [Ascii::LF, Ascii::NUL].include?(byte)
      end

      # The next byte when it comes within ESC_WAIT seconds, else +nil+.
      def read_soon = (@client.read(1) if @client.wait_readable(ESC_WAIT))

      # The UTF-8 character whose first byte is +lead+; +nil+ when the bytes
      # after it do not make one.
      def read_utf8(lead)
        bytes = lead.b
        utf8_tail_size(lead.ord).times do
          tail = read_soon
          return unless tail && utf8_tail?(tail.ord)

          bytes << tail
        end
        char = bytes.force_encoding(Encoding::UTF_8)
        char if char.valid_encoding?
      end

      def utf8_tail_size(lead)
        if lead >= UTF8_LEAD_4 then 3
        elsif lead >= UTF8_LEAD_3 then 2
        else 1
        end
      end

      def utf8_tail?(byte) = (byte & UTF8_TAIL_MASK) == UTF8_TAIL
    end
  end
end
