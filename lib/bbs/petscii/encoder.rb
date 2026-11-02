# frozen_string_literal: true

module BBS
  module Petscii
    # Turns what a BBS writes into PETSCII. It keeps the cursor's column, so
    # a line of exactly 40 characters, which the C64 wraps by itself, is not
    # followed by an empty one, and it keeps the state of an escape sequence
    # cut in two by separate writes.
    class Encoder
      # What a control character does, by code: the method that handles it.
      CONTROL_ACTIONS = {
        Ascii::ESC => :start_escape, Ascii::CR => :carriage_return, Ascii::LF => :line_feed,
        Ascii::BS => :backspace, Ascii::TAB => :tab, Ascii::FF => :clear, CLEAR.ord => :clear,
        HOME.ord => :home, RVS_ON.ord => :rvs_on, RVS_OFF.ord => :rvs_off
      }.freeze
      # The pen after a reset: no bold, no dim, the default colour.
      PLAIN_PEN = { bold: false, dim: false, fg: nil }.freeze
      # Creates an encoder at column 0 with no colour, reverse video or
      # escape sequence pending.
      def initialize
        @col     = 0
        @wrapped = false
        @lone_cr = false
        @rvs     = false
        @pen     = PLAIN_PEN
        @color   = nil
        @esc     = nil
      end

      # Returns the PETSCII bytes (a binary String) for +data+, UTF-8 text
      # with ANSI escape sequences. Letters swap case, box drawing and other
      # symbols become the nearest PETSCII glyph (GLYPHS, accents dropped,
      # <tt>?</tt> when there is none), SGR colours and reverse video become
      # colour and RVS codes, cursor moves become cursor control codes, and
      # <tt>\e[2J</tt> clears the screen. Other sequences are dropped. The
      # encoder's column and colour state carry over to the next call.
      def encode(data)
        text = data.to_s.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub('?') unless text.valid_encoding?
        out  = +''.b
        text.each_char { |ch| feed(ch, out) }
        out
      end

      private

      def feed(ch, out)
        return escape(ch, out) if @esc
        return if swallowed_lf?(ch, out)

        action = CONTROL_ACTIONS[ch.ord]
        action ? send(action, out) : character(ch, out)
      end

      # A CR alone moved the C64's cursor down a row as well: the next
      # character takes it back up, unless it is the LF that follows. True
      # when +ch+ is that LF.
      def swallowed_lf?(ch, out)
        return false unless @lone_cr

        @lone_cr = false
        return true if ch == "\n"

        out << bytes(UP)
        false
      end

      def character(ch, out)
        o = ch.ord
        if CONTROLS.include?(o)
          out << o.chr
          @color = ch if COLORS.include?(ch)
        elsif o >= Ascii::SPACE && o != Ascii::DEL && !C1_CONTROLS.cover?(o)
          text(ch, out)
        end
      end

      # ── Control characters ──────────────────────────────────────────────

      def start_escape(_out) = @esc = +''

      def carriage_return(out)
        line_feed(out)
        @lone_cr = true
      end

      # RETURN on the C64 also ends reverse mode.
      def line_feed(out)
        unless @wrapped
          out << Ansi::CR
          @rvs = false
        end
        at_column(0)
      end

      def backspace(out)
        out << bytes(LEFT)
        move(-1)
      end

      def tab(out) = text('  ', out)

      def clear(out)
        out << bytes(CLEAR)
        at_column(0)
      end

      def home(out)
        out << bytes(HOME)
        at_column(0)
      end

      def rvs_on(out)
        out << bytes(RVS_ON)
        @rvs = true
      end

      def rvs_off(out)
        out << bytes(RVS_OFF)
        @rvs = false
      end

      def at_column(col)
        @col     = col
        @wrapped = false
      end

      def move(delta) = at_column((@col + delta).clamp(0, COLS - 1))

      def bytes(codes) = Petscii.bytes(codes)
    end
  end
end

require_relative 'encoder/text'
require_relative 'encoder/escapes'
require_relative 'encoder/sgr'
