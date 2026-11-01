# frozen_string_literal: true

module BBS
  # The Commodore 64's character set on the telnet line: a 40×25 screen,
  # colours and cursor moves as single control bytes, and the lowercase
  # character set (letters swap case against ASCII).
  #
  # A session switched with <tt>session.petscii!</tt> sends everything it writes
  # through an Encoder, so the code above it keeps writing UTF-8 text with
  # ANSI colours and cursor moves (a Flow, a FakeOS, a door), and reads the
  # C64's keys as the usual key symbols. PETSCII control codes can be
  # written directly too: they are the C0 and C1 code points of a UTF-8
  # string, so <tt>"#{BBS::Petscii::YELLOW}READY."</tt> is yellow on the C64.
  module Petscii
    # Control code: text colour white.
    WHITE       = "\u0005"
    # Control code: text colour red.
    RED         = "\u001c"
    # Control code: text colour green.
    GREEN       = "\u001e"
    # Control code: text colour blue.
    BLUE        = "\u001f"
    # Control code: text colour orange.
    ORANGE      = "\u0081"
    # Control code: text colour black.
    BLACK       = "\u0090"
    # Control code: text colour brown.
    BROWN       = "\u0095"
    # Control code: text colour light red.
    LIGHT_RED   = "\u0096"
    # Control code: text colour dark grey.
    DARK_GREY   = "\u0097"
    # Control code: text colour medium grey.
    GREY        = "\u0098"
    # Control code: text colour light green.
    LIGHT_GREEN = "\u0099"
    # Control code: text colour light blue.
    LIGHT_BLUE  = "\u009a"
    # Control code: text colour light grey.
    LIGHT_GREY  = "\u009b"
    # Control code: text colour purple.
    PURPLE      = "\u009c"
    # Control code: text colour yellow.
    YELLOW      = "\u009e"
    # Control code: text colour cyan.
    CYAN        = "\u009f"

    # Control code: clears the screen and homes the cursor.
    CLEAR     = "\u0093"
    # Control code: moves the cursor to the top left.
    HOME      = "\u0013"
    # Control code: turns reverse video on.
    RVS_ON    = "\u0012"
    # Control code: turns reverse video off.
    RVS_OFF   = "\u0092"
    # Control code: moves the cursor up.
    UP        = "\u0091"
    # Control code: moves the cursor down.
    DOWN      = "\u0011"
    # Control code: moves the cursor left.
    LEFT      = "\u009d"
    # Control code: moves the cursor right.
    RIGHT     = "\u001d"
    # Control code: deletes the character left of the cursor (the INST/DEL key).
    DEL       = "\u0014"
    # Control code: rings the bell, where the terminal program supports it.
    BELL      = "\u0007"
    # Control code: switches to the lowercase character set.
    LOWERCASE = "\u000e"
    # Control code: switches to the uppercase/graphics character set.
    UPPERCASE = "\u008e"
    # Control code: locks the character set, so C= + Shift no longer
    # switches it. Its byte is the
    # backspace of ASCII, so the Encoder moves the cursor left on it: send
    # it raw (Telnet#petscii! does).
    LOCK_CASE = "\u0008"

    # Width of the C64 screen in characters.
    COLS = 40
    # Height of the C64 screen in lines.
    ROWS = 25

    # Key code: RETURN.
    KEY_RETURN     = 0x0d
    # Key code: RUN/STOP, an escape key.
    KEY_RUN_STOP   = 0x03
    # Key code: the left arrow key (top left), an escape key.
    KEY_LEFT_ARROW = 0x5f
    # Key code: F1.
    KEY_F1 = 0x85
    # Key code: F2 (Shift-F1).
    KEY_F2 = 0x89
    # Key code: F3.
    KEY_F3 = 0x86
    # Key code: F4 (Shift-F3).
    KEY_F4 = 0x8a
    # Key code: F5.
    KEY_F5 = 0x87
    # Key code: F6 (Shift-F5).
    KEY_F6 = 0x8b
    # Key code: F7.
    KEY_F7 = 0x88
    # Key code: F8 (Shift-F7).
    KEY_F8 = 0x8c
    # Key code: the pound sign.
    KEY_POUND      = 0x5c
    # Key code: the up arrow key.
    KEY_UP_ARROW   = 0x5e
    # Key code: Shift-SPACE.
    SHIFT_SPACE    = 0xa0

    # Codes that are the same in PETSCII and ASCII: space, digits,
    # punctuation and <tt>@</tt>.
    SAME_AS_ASCII = 0x20..0x40
    # The left bracket, the same in PETSCII and ASCII.
    LEFT_BRACKET  = 0x5b
    # The right bracket, the same in PETSCII and ASCII.
    RIGHT_BRACKET = 0x5d
    # The codes of A-Z in ASCII, and of the unshifted (lowercase) letters in
    # the C64's lowercase character set.
    ASCII_UPPER = 0x41..0x5a
    # The codes of a-z in ASCII, and of shifted (capital) letters some C64
    # terminal programs send.
    ASCII_LOWER = 0x61..0x7a
    # The codes of the shifted (capital) letters the C64 keyboard sends.
    SHIFTED_LETTERS = 0xc1..0xda
    # The distance between a letter's lowercase and uppercase ASCII codes.
    CASE_OFFSET  = 0x20
    # The distance between ASCII A-Z and the C64's shifted letters.
    SHIFT_OFFSET = 0x80
    # The C1 control range, never printed as a character.
    C1_CONTROLS = 0x80..0x9f

    # SGR parameter: reset.
    SGR_RESET = 0
    # SGR parameter: bold.
    SGR_BOLD = 1
    # SGR parameter: dim.
    SGR_DIM = 2
    # SGR parameter: reverse video.
    SGR_REVERSE = 7
    # SGR parameter: neither bold nor dim.
    SGR_NORMAL = 22
    # SGR parameter: reverse video off.
    SGR_REVERSE_OFF = 27
    # SGR parameters of the normal foreground colours.
    SGR_FG = 30..37
    # SGR parameter: default foreground colour.
    SGR_FG_DEFAULT = 39
    # SGR parameters of the bright foreground colours.
    SGR_FG_BRIGHT = 90..97
    # SGR parameters that start an extended colour, foreground and
    # background.
    SGR_EXTENDED = [38, 48].freeze
    # The extended colour kind of a 256-colour index (one more parameter);
    # any other kind is RGB (three more).
    SGR_INDEXED = 5
    # The ANSI colour index of white, the default text colour.
    ANSI_WHITE = 7

    # The columns a closing quote needs: the quote, a cursor left and a space.
    QUOTE_ROOM = 3
    # A character the C64 shows as it is in one cell: printable ASCII and £.
    PLAIN_CELL = /\A[ -~£]\z/
    # A combining mark, dropped with the accent of a decomposed letter.
    COMBINING_MARK = /\p{Mn}/
    # The final byte of an escape sequence the Encoder acts on.
    ESCAPE_FINAL = /[A-Za-z~@`]/

    # The control bytes that go to the C64 as they are.
    CONTROLS = [0x05, 0x07, 0x0e, 0x11, 0x12, 0x13, 0x14, 0x1c, 0x1d, 0x1e, 0x1f,
                0x81, 0x8e, *0x90..0x9f].freeze

    # The PETSCII colours for the normal ANSI colours 0-7 (SGR 30-37). Black
    # is dark grey: the C64's terminal screen is black, and a black-on-grey
    # door must stay readable.
    ANSI_DARK   = [DARK_GREY, RED, GREEN, ORANGE, BLUE, PURPLE, CYAN, LIGHT_GREY].freeze
    # The PETSCII colours for the bright ANSI colours 0-7 (SGR 90-97, or
    # 30-37 with bold); black is dark grey here too.
    ANSI_BRIGHT = [DARK_GREY, LIGHT_RED, LIGHT_GREEN, YELLOW, LIGHT_BLUE, PURPLE, CYAN, WHITE].freeze
    # The colour of plain text, after an SGR reset.
    DEFAULT     = LIGHT_GREY
    # All sixteen colour control codes; the Encoder tracks the last one sent.
    COLORS      = [WHITE, RED, GREEN, BLUE, ORANGE, BLACK, BROWN, LIGHT_RED, DARK_GREY, GREY,
                   LIGHT_GREEN, LIGHT_BLUE, LIGHT_GREY, PURPLE, YELLOW, CYAN].freeze

    # Unicode -> the bytes of the lowercase set (box drawing, blocks, the
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

    # Translates a +byte+ the C64 sent into a key the way BBS::Telnet#readkey
    # returns keys: a Symbol (+:enter+, +:backspace+ for DEL and for the ASCII
    # backspace and delete some terminal programs send, the arrows, +:home+,
    # +:escape+ for RUN/STOP and the left arrow key, +:f1+ ... +:f8+), a
    # one-character String with the letter case swapped back to ASCII, or
    # +nil+ for a byte that is not a key.
    def self.key(byte)
      case byte
      when KEY_RETURN      then :enter
      when DEL.ord, Ascii::BS, Ascii::DEL then :backspace
      when DOWN.ord        then :down
      when UP.ord          then :up
      when RIGHT.ord       then :right
      when LEFT.ord        then :left
      when HOME.ord        then :home
      when KEY_RUN_STOP, KEY_LEFT_ARROW then :escape
      when KEY_F1          then :f1
      when KEY_F2          then :f2
      when KEY_F3          then :f3
      when KEY_F4          then :f4
      when KEY_F5          then :f5
      when KEY_F6          then :f6
      when KEY_F7          then :f7
      when KEY_F8          then :f8
      when ASCII_UPPER     then (byte + CASE_OFFSET).chr
      when SHIFTED_LETTERS then (byte - SHIFT_OFFSET).chr
      when ASCII_LOWER     then (byte - CASE_OFFSET).chr
      when SAME_AS_ASCII, LEFT_BRACKET, RIGHT_BRACKET then byte.chr
      when KEY_POUND       then '£'
      when KEY_UP_ARROW    then '^'
      when SHIFT_SPACE     then ' '
      end
    end

    # Returns the binary String of bytes for +codes+, a String of PETSCII
    # code points (such as the constants of this module).
    def self.bytes(codes) = codes.each_char.map { |c| c.ord.chr }.join.b

    # Returns +char+ when an Encoder shows it in one screen cell (a letter,
    # a digit, a sign, a glyph of GLYPHS or an accented letter, which
    # loses its accent), <tt>'?'</tt> when it would take more cells or none.
    def self.cell(char)
      return char if char.match?(PLAIN_CELL)

      glyph = GLYPHS[char]
      return char if glyph && glyph.length == 1

      base = char.unicode_normalize(:nfkd).gsub(COMBINING_MARK, '')
      base.length == 1 && base.ascii_only? ? char : '?'
    end

    # Letters and signs the C64 has no glyph for, spelled in ASCII by
    # ::plain where the Encoder would show a question mark.
    SPELLED = { 'æ' => 'ae', 'Æ' => 'Ae', 'œ' => 'oe', 'Œ' => 'Oe', 'ø' => 'o', 'Ø' => 'O', 'ł' => 'l', 'Ł' => 'L',
                'đ' => 'd', 'Đ' => 'D', 'þ' => 'th', 'Þ' => 'Th', 'ð' => 'd', 'Ð' => 'D', 'ı' => 'i',
                '″' => '"', '′' => "'", '¡' => '!', '¿' => '?', '§' => 'S.', '¶' => '' }.freeze

    # A character ::plain converts: anything but printable ASCII and ESC, so
    # ANSI colours pass through.
    UNPLAIN = /[^ -~\e]/

    # Returns +text+ in characters the C64 shows one to a cell, so that it
    # wraps where it is counted: the typography of GLYPHS that has an ASCII
    # form becomes it (an ellipsis three dots, a dash a hyphen), the box
    # drawing and block glyphs of the Encoder stay, the letters of SPELLED
    # are spelled out, accented letters lose the accent, and anything else
    # is a question mark. ANSI escape sequences are kept.
    #
    #   BBS::Petscii.plain('Ærø – “café”…')   # => 'Aero - "cafe"...'
    def self.plain(text)
      text.to_s.gsub(UNPLAIN) do |c|
        glyph = GLYPHS[c]
        next glyph if glyph&.ascii_only?
        next c if glyph
        next SPELLED[c] if SPELLED.key?(c)

        base = c.unicode_normalize(:nfkd).gsub(COMBINING_MARK, '')
        base.length == 1 && base.ascii_only? ? base : '?'
      end
    end

    # Turns what a BBS writes into PETSCII. It keeps the cursor's column, so
    # a line of exactly 40 characters, which the C64 wraps by itself, is not
    # followed by an empty one, and it keeps the state of an escape sequence
    # cut in two by separate writes.
    class Encoder
      # Creates an encoder at column 0 with no colour, reverse video or
      # escape sequence pending.
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

        if @lone_cr
          @lone_cr = false
          return if ch == "\n"

          out << bytes(Petscii::UP)
        end

        o = ch.ord
        case o
        when Ascii::ESC then @esc = +''
        when Ascii::CR  then newline(out); @lone_cr = true
        when Ascii::LF  then newline(out)
        when Ascii::BS  then out << bytes(Petscii::LEFT); move(-1)
        when Ascii::TAB then text('  ', out)
        when Ascii::FF  then clear(out)
        when Petscii::CLEAR.ord   then clear(out)
        when Petscii::HOME.ord    then out << o.chr; @col = 0; @wrapped = false
        when Petscii::RVS_ON.ord  then out << o.chr; @rvs = true
        when Petscii::RVS_OFF.ord then out << o.chr; @rvs = false
        else
          if Petscii::CONTROLS.include?(o)
            out << o.chr
            @color = ch if Petscii::COLORS.include?(ch)
          elsif o >= Ascii::SPACE && o != Ascii::DEL && !Petscii::C1_CONTROLS.cover?(o)
            text(ch, out)
          end
        end
      end

      # RETURN on the C64 also ends reverse mode.
      def newline(out)
        unless @wrapped
          out << Ansi::CR
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
          quote_off(out) if g == '"'
          next if Petscii::CONTROLS.include?(g.ord)

          @col += 1
          @wrapped = false
          next unless @col >= Petscii::COLS

          @col     = 0
          @wrapped = true
        end
      end

      # A " puts the C64 screen editor in quote mode, where colour and cursor
      # codes show as reversed symbols instead of working until the next "
      # or RETURN. A second " ends it; the cursor goes back onto it and a
      # space covers it. Too near the right edge the second " would wrap the
      # line, so there the quote mode stays until the RETURN.
      def quote_off(out)
        return if @col > Petscii::COLS - Petscii::QUOTE_ROOM

        out << bytes("\"#{Petscii::LEFT} #{Petscii::LEFT}")
      end

      def glyph(ch)
        o = ch.ord
        return (o + Petscii::SHIFT_OFFSET).chr(Encoding::UTF_8) if Petscii::ASCII_UPPER.cover?(o)
        return (o - Petscii::CASE_OFFSET).chr if Petscii::ASCII_LOWER.cover?(o)
        return ch if Petscii::SAME_AS_ASCII.cover?(o) || o == Petscii::LEFT_BRACKET || o == Petscii::RIGHT_BRACKET

        case ch
        when '█' then @rvs ? "#{Petscii::RVS_OFF} #{Petscii::RVS_ON}" : "#{Petscii::RVS_ON} #{Petscii::RVS_OFF}"
        when '▀' then "#{Petscii::RVS_ON}#{Petscii::GLYPHS['▄']}#{Petscii::RVS_OFF}"
        when '▐' then "#{Petscii::RVS_ON}#{Petscii::GLYPHS['▌']}#{Petscii::RVS_OFF}"
        else
          mapped = Petscii::GLYPHS[ch]
          return mapped if mapped

          base = ch.unicode_normalize(:nfkd).gsub(Petscii::COMBINING_MARK, '')
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
        return @esc = nil if @esc.length > Ansi::MAX_CSI_LENGTH
        return unless ch.match?(Petscii::ESCAPE_FINAL)

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
          out << bytes("#{Ansi::CR}#{Petscii::UP}#{Petscii::RIGHT * (n - 1)}") unless @wrapped && n == 1
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
          when Petscii::SGR_RESET       then @bold = false; @dim = false; @fg = nil; rvs = false
          when Petscii::SGR_BOLD        then @bold = true
          when Petscii::SGR_DIM         then @dim = true
          when Petscii::SGR_NORMAL      then @bold = false; @dim = false
          when Petscii::SGR_REVERSE     then rvs = true
          when Petscii::SGR_REVERSE_OFF then rvs = false
          when Petscii::SGR_FG          then @fg = [c - Petscii::SGR_FG.first, false]
          when Petscii::SGR_FG_BRIGHT   then @fg = [c - Petscii::SGR_FG_BRIGHT.first, true]
          when Petscii::SGR_FG_DEFAULT  then @fg = nil
          when *Petscii::SGR_EXTENDED   then i += codes[i + 1] == Petscii::SGR_INDEXED ? 2 : 4
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
        return Petscii::GREY if @dim && (@fg.nil? || @fg.first == Petscii::ANSI_WHITE)

        index, bright = @fg || [Petscii::ANSI_WHITE, false]
        (bright || @bold ? Petscii::ANSI_BRIGHT : Petscii::ANSI_DARK)[index]
      end
    end
  end
end
