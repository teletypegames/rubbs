# frozen_string_literal: true

module BBS
  module Telnet
    # The ANSI escape sequences of the special keys (cursor keys, function
    # keys, Alt and other modifiers) decoded for Telnet::Keys#readkey;
    # mouse reports go on to Telnet::Mouse.
    module Escapes
      # The second byte of an ESC sequence that starts an SS3 sequence.
      SS3_START = 'O'
      # The final bytes of the cursor keys, the same after CSI and SS3.
      CURSOR_KEYS = { 'A' => :up, 'B' => :down, 'C' => :right, 'D' => :left,
                      'H' => :home, 'F' => :end }.freeze
      # The keys sent as SS3 and a final byte: the cursor keys and F1-F4.
      SS3_KEYS = CURSOR_KEYS.merge('P' => :f1, 'Q' => :f2, 'R' => :f3, 'S' => :f4).freeze
      # The keys sent as CSI and a letter: the cursor keys and Shift-Tab.
      CSI_KEYS = CURSOR_KEYS.merge('Z' => :shift_tab).freeze
      # The final byte of a CSI key sent as a number: <tt>ESC [ 15 ~</tt>.
      TILDE = '~'
      # The keys sent as <tt>ESC [ number ~</tt>, by number.
      TILDE_KEYS = {
        1 => :home, 7 => :home, 2 => :insert, 3 => :delete, 4 => :end, 8 => :end,
        5 => :page_up, 6 => :page_down,
        11 => :f1, 12 => :f2, 13 => :f3, 14 => :f4, 15 => :f5, 17 => :f6,
        18 => :f7, 19 => :f8, 20 => :f9, 21 => :f10, 23 => :f11, 24 => :f12
      }.freeze
      # The modifier prefixes by xterm's second CSI parameter:
      # <tt>ESC [ 1 ; 2 A</tt> is Shift-Up, <tt>ESC [ 15 ; 5 ~</tt> Ctrl-F5.
      MODIFIERS = { 2 => 'shift', 3 => 'alt', 5 => 'ctrl', 6 => 'ctrl_shift' }.freeze

      private

      # A CSI or SS3 sequence after ESC: a key Symbol, an Alt-modified key,
      # a MouseEvent, or +:escape+.
      def read_escape_sequence = escaped_key(read_soon)

      def escaped_key(char)
        case char
        when nil            then :escape
        when Ansi::CSI_BYTE then read_csi
        when SS3_START      then SS3_KEYS.fetch(@client.read(1), :escape)
        when Ansi::CR       then alt_enter
        else alt_key(char)
        end
      end

      def alt_enter
        @after_cr = true
        :alt_enter
      end

      def alt_key(char) = Ascii::PRINTABLE.cover?(char.ord) ? :"alt_#{char.downcase}" : :escape

      def read_csi
        params, final = read_csi_parts
        return :escape unless final

        mouse_report(params, final) || with_modifier(csi_key(final, params), params)
      end

      # The parameter bytes and the final byte of a CSI sequence; +nil+ when
      # the line ends or the parameters run over Ansi::MAX_CSI_LENGTH.
      def read_csi_parts
        params = +''
        while params.length <= Ansi::MAX_CSI_LENGTH
          char = @client.read(1) or return
          return [params, char] if char.match?(Ansi::CSI_FINAL)

          params << char
        end
      end

      def with_modifier(key, params)
        prefix = MODIFIERS[params.split(';')[1].to_i]
        return key unless prefix && key != :escape

        :"#{prefix}_#{key}"
      end

      def csi_key(final, params)
        return TILDE_KEYS.fetch(params.to_i, :escape) if final == TILDE

        CSI_KEYS.fetch(final, :escape)
      end
    end
  end
end
