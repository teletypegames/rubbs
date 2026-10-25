# frozen_string_literal: true

module BBS
  # The Commodore 64's character set on the telnet line: a 40×25 screen,
  # colours and cursor moves as single control bytes, and the lowercase
  # character set (letters swap case against ASCII).
  #
  # A session switched with `session.petscii!` sends everything it writes
  # through an Encoder, so the code above it keeps writing UTF-8 text with
  # ANSI colours and cursor moves (a Flow, a FakeOS, a door), and reads the
  # C64's keys as the usual key symbols. PETSCII control codes can be
  # written directly too: they are the C0 and C1 code points of a UTF-8
  # string, so `"#{BBS::Petscii::YELLOW}READY."` is yellow on the C64.
  module Petscii
    WHITE       = "\u0005"
    RED         = "\u001c"
    GREEN       = "\u001e"
    BLUE        = "\u001f"
    ORANGE      = "\u0081"
    BLACK       = "\u0090"
    BROWN       = "\u0095"
    LIGHT_RED   = "\u0096"
    DARK_GREY   = "\u0097"
    GREY        = "\u0098"
    LIGHT_GREEN = "\u0099"
    LIGHT_BLUE  = "\u009a"
    LIGHT_GREY  = "\u009b"
    PURPLE      = "\u009c"
    YELLOW      = "\u009e"
    CYAN        = "\u009f"

    CLEAR     = "\u0093"
    HOME      = "\u0013"
    RVS_ON    = "\u0012"
    RVS_OFF   = "\u0092"
    UP        = "\u0091"
    DOWN      = "\u0011"
    LEFT      = "\u009d"
    RIGHT     = "\u001d"
    DEL       = "\u0014"
    BELL      = "\u0007"
    LOWERCASE = "\u000e"
    UPPERCASE = "\u008e"
    # C= + Shift no longer switches the character set. Its byte is the
    # backspace of ASCII, so the Encoder moves the cursor left on it: send
    # it raw (Telnet#petscii! does).
    LOCK_CASE = "\u0008"

    COLS = 40
    ROWS = 25

    # The control bytes that go to the C64 as they are.
    CONTROLS = [0x05, 0x07, 0x0e, 0x11, 0x12, 0x13, 0x14, 0x1c, 0x1d, 0x1e, 0x1f,
                0x81, 0x8e, *0x90..0x9f].freeze

    # ANSI colours 0–7, dark and bright. Black is dark grey: the C64's
    # terminal screen is black, and a black-on-grey door must stay readable.
    ANSI_DARK   = [DARK_GREY, RED, GREEN, ORANGE, BLUE, PURPLE, CYAN, LIGHT_GREY].freeze
    ANSI_BRIGHT = [DARK_GREY, LIGHT_RED, LIGHT_GREEN, YELLOW, LIGHT_BLUE, PURPLE, CYAN, WHITE].freeze
    DEFAULT     = LIGHT_GREY
    COLORS      = [WHITE, RED, GREEN, BLUE, ORANGE, BLACK, BROWN, LIGHT_RED, DARK_GREY, GREY,
                   LIGHT_GREEN, LIGHT_BLUE, LIGHT_GREY, PURPLE, YELLOW, CYAN].freeze

    # Unicode → the bytes of the lowercase set (box drawing, blocks, the
    # typography of the modern board). Letters, digits and most punctuation
    # are mapped by code in Encoder#glyph.
    GLYPHS = {
      '─' => "\u00c0", '━' => "\u00c0", '═' => "\u00c0", '│' => "\u00dd", '┃' => "\u00dd", '║' => "\u00dd",
      '┌' => "\u00b0", '╔' => "\u00b0", '╭' => "\u00b0", '┐' => "\u00ae", '╗' => "\u00ae", '╮' => "\u00ae",
      '└' => "\u00ad", '╚' => "\u00ad", '╰' => "\u00ad", '┘' => "\u00bd", '╝' => "\u00bd", '╯' => "\u00bd",
      '├' => "\u00ab", '╠' => "\u00ab", '┤' => "\u00b3", '╣' => "\u00b3", '┬' => "\u00b2", '╦' => "\u00b2",
      '┴' => "\u00b1", '╩' => "\u00b1", '┼' => "\u00db", '╬' => "\u00db",
      '░' => "\u00a6", '▒' => "\u00a6", '▓' => "\u00a6", '▄' => "\u00a2", '▌' => "\u00a1", '▁' => "\u00a4",
      '▔' => "\u00a3", '✓' => "\u00ba", '✔' => "\u00ba",
      '£' => "\u005c", '←' => "\u005f", '↑' => "\u005e", '^' => "\u005e", '_' => "\u00a4", '|' => "\u00dd",
      '\\' => '/', '`' => "'", '{' => '(', '}' => ')', '~' => '-',
      '–' => '-', '—' => '-', '―' => '-', '‘' => "'", '’' => "'", '“' => '"', '”' => '"', '„' => '"',
      '…' => '...', '·' => '.', '•' => '*', '●' => '*', '◆' => '*', '★' => '*', '■' => '*', '☼' => '*',
      '○' => 'o', '◄' => '<', '◀' => '<', '‹' => '<', '«' => '<', '►' => '>', '▶' => '>', '▸' => '>',
      '›' => '>', '»' => '>', '→' => '>', '↓' => 'v', '×' => 'x', '°' => 'o', '≈' => '-', '∿' => '-',
      '≋' => '-', " " => ' ', 'ß' => 'ss', 'π' => 'pi'
    }.freeze

    # A key of the C64 as BBS::Telnet#readkey returns keys: a Symbol, a
    # one-character String, or nil for a byte that is not a key.
    def self.key(byte)
      case byte
      when 0x0d        then :enter
      when 0x14        then :backspace
      when 0x11        then :down
      when 0x91        then :up
      when 0x1d        then :right
      when 0x9d        then :left
      when 0x13        then :home
      when 0x03, 0x5f  then :escape # RUN/STOP and ←, the C64's escape keys
      when 0x85        then :f1
      when 0x89        then :f2
      when 0x86        then :f3
      when 0x8a        then :f4
      when 0x87        then :f5
      when 0x8b        then :f6
      when 0x88        then :f7
      when 0x8c        then :f8
      when 0x41..0x5a  then (byte + 0x20).chr
      when 0xc1..0xda  then (byte - 0x80).chr
      when 0x61..0x7a  then (byte - 0x20).chr
      when 0x20..0x40, 0x5b, 0x5d then byte.chr
      when 0x5c        then '£'
      when 0x5e        then '^'
      when 0xa0        then ' '
      end
    end

    # The bytes of a string of PETSCII code points, e.g. of the constants.
    def self.bytes(codes) = codes.each_char.map { |c| c.ord.chr }.join.b

    # Turns what a BBS writes into PETSCII. It keeps the cursor's column, so
    # a line of exactly 40 characters, which the C64 wraps by itself, is not
    # followed by an empty one, and it keeps the state of an escape sequence
    # cut in two by separate writes.
    class Encoder
      def initialize
        @col     = 0
        @wrapped = false
        @lone_cr = false
        @rvs     = false
        @bold    = false
        @dim     = false
        @fg      = nil
        @color   = nil
        @esc     = nil
      end

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

        if @lone_cr
          @lone_cr = false
          return if ch == "\n"

          out << bytes(Petscii::UP)
        end

        o = ch.ord
        case o
        when 0x1b then @esc = +''
        when 0x0d then newline(out); @lone_cr = true
        when 0x0a then newline(out)
        when 0x08 then out << bytes(Petscii::LEFT); move(-1)
        when 0x09 then text('  ', out)
        when 0x0c then clear(out)
        when 0x93 then clear(out)
        when 0x13 then out << o.chr; @col = 0; @wrapped = false
        when 0x12 then out << o.chr; @rvs = true
        when 0x92 then out << o.chr; @rvs = false
        else
          if Petscii::CONTROLS.include?(o)
            out << o.chr
            @color = ch if Petscii::COLORS.include?(ch)
          elsif o >= 0x20 && o != 0x7f && !(0x80..0x9f).cover?(o)
            text(ch, out)
          end
        end
      end

      # RETURN on the C64 also ends reverse mode.
      def newline(out)
        unless @wrapped
          out << "\r"
          @rvs = false
        end
        @col     = 0
        @wrapped = false
      end

      def clear(out)
        out << bytes(Petscii::CLEAR)
        @col     = 0
        @wrapped = false
      end

      def move(delta)
        @col     = (@col + delta).clamp(0, Petscii::COLS - 1)
        @wrapped = false
      end

      # Control codes keep the column; every other character takes one.
      def text(ch, out)
        glyph(ch).each_char do |g|
          out << g.ord.chr
          next if Petscii::CONTROLS.include?(g.ord)

          @col += 1
          @wrapped = false
          next unless @col >= Petscii::COLS

          @col     = 0
          @wrapped = true
        end
      end

      def glyph(ch)
        o = ch.ord
        return (o + 0x80).chr(Encoding::UTF_8) if o.between?(0x41, 0x5a)
        return (o - 0x20).chr if o.between?(0x61, 0x7a)
        return ch if o.between?(0x20, 0x40) || o == 0x5b || o == 0x5d

        case ch
        when '█' then @rvs ? "#{Petscii::RVS_OFF} #{Petscii::RVS_ON}" : "#{Petscii::RVS_ON} #{Petscii::RVS_OFF}"
        when '▀' then "#{Petscii::RVS_ON}\u00a2#{Petscii::RVS_OFF}"
        when '▐' then "#{Petscii::RVS_ON}\u00a1#{Petscii::RVS_OFF}"
        else
          mapped = Petscii::GLYPHS[ch]
          return mapped if mapped

          base = ch.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '')
          base.ascii_only? && !base.empty? && base != ch ? base.each_char.map { |c| glyph(c) }.join : '?'
        end
      end

      def bytes(codes) = Petscii.bytes(codes)

      # ── ANSI ──────────────────────────────────────────────────────────────

      def escape(ch, out)
        if @esc.empty?
          case ch
          when '[' then @esc << ch
          when '(', ')' then @esc << ch
          else @esc = nil
          end
          return
        end
        if @esc.start_with?('(', ')')
          @esc = nil
          return
        end

        @esc << ch
        return @esc = nil if @esc.length > 32
        return unless ch.match?(/[A-Za-z~@`]/)

        params = @esc[1...-1]
        @esc   = nil
        csi(params, ch, out)
      end

      def csi(params, final, out)
        nums = params.delete('?').split(';').map(&:to_i)
        n    = [nums.first.to_i, 1].max
        case final
        when 'm' then sgr(nums.empty? ? [0] : nums, out)
        when 'J' then clear(out) if nums.first == 2
        when 'H', 'f'
          out << bytes(Petscii::HOME)
          @col = 0
          row, col = nums
          out << bytes(Petscii::DOWN * ([row.to_i, 1].max - 1))
          out << bytes(Petscii::RIGHT * ([col.to_i, 1].max - 1))
          move([col.to_i, 1].max - 1)
        when 'A' then out << bytes(Petscii::UP * n)
        when 'B' then out << bytes(Petscii::DOWN * n)
        when 'C' then out << bytes(Petscii::RIGHT * n); move(n)
        when 'D' then out << bytes(Petscii::LEFT * n); move(-n)
        when 'G'
          out << bytes("\r#{Petscii::UP}#{Petscii::RIGHT * (n - 1)}") unless @wrapped && n == 1
          @col = 0
          move(n - 1)
        end
      end

      def sgr(codes, out)
        rvs = @rvs
        i = 0
        while i < codes.size
          c = codes[i]
          case c
          when 0 then @bold = false; @dim = false; @fg = nil; rvs = false
          when 1 then @bold = true
          when 2 then @dim = true
          when 22 then @bold = false; @dim = false
          when 7 then rvs = true
          when 27 then rvs = false
          when 30..37 then @fg = [c - 30, false]
          when 90..97 then @fg = [c - 90, true]
          when 39 then @fg = nil
          when 38, 48 then i += codes[i + 1] == 5 ? 2 : 4
          end
          i += 1
        end
        if rvs != @rvs
          out << bytes(rvs ? Petscii::RVS_ON : Petscii::RVS_OFF)
          @rvs = rvs
        end
        color = current_color
        return if color == @color

        out << bytes(color)
        @color = color
      end

      def current_color
        return Petscii::DEFAULT if @fg.nil? && !@bold && !@dim
        return Petscii::GREY if @dim && (@fg.nil? || @fg.first == 7)

        index, bright = @fg || [7, false]
        (bright || @bold ? Petscii::ANSI_BRIGHT : Petscii::ANSI_DARK)[index]
      end
    end
  end
end
