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

    # The keys the C64 sends that are not letters or signs, by byte: the
    # key symbols BBS::Telnet#readkey returns. DEL, and the ASCII backspace
    # and delete some terminal programs send, are +:backspace+; RUN/STOP
    # and the left arrow key are +:escape+; Shift-F1 is F2 and so on; the
    # pound sign, the up arrow and Shift-SPACE are the characters they show.
    KEYS = {
      0x0d => :enter, 0x14 => :backspace, 0x08 => :backspace, 0x7f => :backspace,
      0x11 => :down, 0x91 => :up, 0x1d => :right, 0x9d => :left, 0x13 => :home,
      0x03 => :escape, 0x5f => :escape,
      0x85 => :f1, 0x89 => :f2, 0x86 => :f3, 0x8a => :f4, 0x87 => :f5, 0x8b => :f6, 0x88 => :f7, 0x8c => :f8,
      0x5c => '£', 0x5e => '^', 0xa0 => ' '
    }.freeze

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

    # ── The glyph table ───────────────────────────────────────────────────
    # The graphics of the C64 by the Unicode character they look like, as
    # PETSCII codes. The lowercase set (the Encoder's) and the
    # uppercase/graphics set (BBS::Petscii::Canvas) share most of them.

    # Graphics both character sets have at the same code: the box drawing
    # with square corners, the blocks, £ ↑ ←.
    GRAPHICS = {
      '─' => 0xc0, '│' => 0xdd, '┼' => 0xdb, '┌' => 0xb0, '┐' => 0xae, '└' => 0xad, '┘' => 0xbd,
      '├' => 0xab, '┤' => 0xb3, '┬' => 0xb2, '┴' => 0xb1,
      '▌' => 0xa1, '▄' => 0xa2, '▔' => 0xa3, '▁' => 0xa4, '▒' => 0xa6,
      '▖' => 0xbb, '▗' => 0xac, '▘' => 0xbe, '▝' => 0xbc, '▚' => 0xbf,
      '£' => 0x5c, '↑' => 0x5e, '←' => 0x5f
    }.freeze
    # The rounded corners, which only the uppercase/graphics set has; the
    # lowercase set draws them as the square ones (LOOK_ALIKES).
    ROUNDED_CORNERS = { '╭' => 0xd5, '╮' => 0xc9, '╰' => 0xca, '╯' => 0xcb }.freeze
    # The graphics only the uppercase/graphics set has: the rounded
    # corners, the balls, the card suits, the diagonals.
    UPPERCASE_GRAPHICS = ROUNDED_CORNERS.merge(
      '●' => 0xd1, '○' => 0xd7, '♥' => 0xd3, '♠' => 0xc1, '♣' => 0xd8, '♦' => 0xda, 'π' => 0xde,
      '╲' => 0xcd, '╱' => 0xce, '╳' => 0xd6, '◤' => 0xa9, '◥' => 0xdf
    ).freeze
    # The graphics only the lowercase set has: the tick.
    LOWERCASE_GRAPHICS = { '✓' => 0xba, '✔' => 0xba }.freeze
    # Characters the lowercase set shows as the graphic of a look-alike:
    # double and heavy lines as single ones, rounded corners as square ones.
    LOOK_ALIKES = {
      '━' => '─', '═' => '─', '┃' => '│', '║' => '│', '|' => '│',
      '╔' => '┌', '╭' => '┌', '╗' => '┐', '╮' => '┐', '╚' => '└', '╰' => '└', '╝' => '┘', '╯' => '┘',
      '╠' => '├', '╣' => '┤', '╦' => '┬', '╩' => '┴', '╬' => '┼',
      '░' => '▒', '▓' => '▒', '_' => '▁', '^' => '↑'
    }.freeze
    # The typography of a modern board in ASCII, for the characters the C64
    # has no glyph for.
    ASCII_FORMS = {
      '\\' => '/', '`' => "'", '{' => '(', '}' => ')', '~' => '-',
      '–' => '-', '—' => '-', '―' => '-', '‘' => "'", '’' => "'", '“' => '"', '”' => '"', '„' => '"',
      '…' => '...', '·' => '.', '•' => '*', '●' => '*', '◆' => '*', '★' => '*', '■' => '*', '☼' => '*',
      '○' => 'o', '◄' => '<', '◀' => '<', '‹' => '<', '«' => '<', '►' => '>', '▶' => '>', '▸' => '>',
      '›' => '>', '»' => '>', '→' => '>', '↓' => 'v', '×' => 'x', '°' => 'o', '≈' => '-', '∿' => '-',
      '≋' => '-', ' ' => ' ', 'ß' => 'ss', 'π' => 'pi'
    }.freeze
    # What the Encoder writes for a character of the lowercase set: the
    # PETSCII code point of its graphic (GRAPHICS, LOWERCASE_GRAPHICS,
    # LOOK_ALIKES), or its ASCII form.
    GLYPHS = GRAPHICS.merge(LOWERCASE_GRAPHICS)
                     .then { |codes| codes.merge(LOOK_ALIKES.transform_values { |c| codes.fetch(c) }) }
                     .transform_values { |code| code.chr(Encoding::UTF_8) }
                     .merge(ASCII_FORMS).freeze

    # Translates a +byte+ the C64 sent into a key the way BBS::Telnet#readkey
    # returns keys: a Symbol of KEYS (+:enter+, +:backspace+, the arrows,
    # +:home+, +:escape+, +:f1+ ... +:f8+), a one-character String with the
    # letter case swapped back to ASCII, or +nil+ for a byte that is not a
    # key.
    def self.key(byte) = KEYS.fetch(byte) { character(byte) }

    # The character of +byte+, a letter (its case swapped back to ASCII)
    # or a sign; +nil+ for anything else.
    def self.character(byte)
      case byte
      when ASCII_UPPER     then (byte + CASE_OFFSET).chr
      when SHIFTED_LETTERS then (byte - SHIFT_OFFSET).chr
      when ASCII_LOWER     then (byte - CASE_OFFSET).chr
      when SAME_AS_ASCII, LEFT_BRACKET, RIGHT_BRACKET then byte.chr
      end
    end

    # +char+ without its accent: the base letter of a decomposed one, or
    # +char+ itself.
    def self.base(char) = char.unicode_normalize(:nfkd).gsub(COMBINING_MARK, '')

    # Returns the PETSCII colour code, an Integer, that the SGR colour
    # sequence +sgr+ turns into on a PETSCII line (BBS::Petscii::Colors::YE
    # is YELLOW), or +nil+ when it sets no colour.
    def self.color_code(sgr) = Encoder.new.encode(sgr).each_byte.find { |b| COLORS.any? { |c| c.ord == b } }

    # Returns the binary String of bytes for +codes+, a String of PETSCII
    # code points (such as the constants of this module).
    def self.bytes(codes) = codes.each_char.map { |c| c.ord.chr }.join.b

    # Returns +char+ when an Encoder shows it in one screen cell (a letter,
    # a digit, a sign, a glyph of GLYPHS or an accented letter, which
    # loses its accent), <tt>'?'</tt> when it would take more cells or none.
    def self.cell(char)
      return char if char.match?(PLAIN_CELL)

      return char if GLYPHS[char]&.length == 1

      ascii_letter?(base(char)) ? char : '?'
    end

    # Whether +text+ is one ASCII character.
    def self.ascii_letter?(text) = text.length == 1 && text.ascii_only?

    # Letters and signs the C64 has no glyph for, spelled in ASCII by
    # ::plain where the Encoder would show a question mark.
    SPELLED = { 'æ' => 'ae', 'Æ' => 'Ae', 'œ' => 'oe', 'Œ' => 'Oe', 'ø' => 'o', 'Ø' => 'O', 'ł' => 'l', 'Ł' => 'L',
                'đ' => 'd', 'Đ' => 'D', 'þ' => 'th', 'Þ' => 'Th', 'ð' => 'd', 'Ð' => 'D', 'ı' => 'i',
                '″' => '"', '′' => "'", '¡' => '!', '¿' => '?', '§' => 'S.', '¶' => '' }.freeze

    # A character ::plain converts: anything but printable ASCII and ESC, so
    # ANSI colours pass through.
    UNPLAIN = /[^ -~\e]/

    # The characters the C64 has keys and glyphs of its own for. GLYPHS maps
    # them to their PETSCII codes, which happen to be in the ASCII range;
    # ::plain keeps them as they are, so the Encoder still finds them.
    NATIVE = %w[£ ← ↑].freeze

    # Returns +text+ in characters the C64 shows one to a cell, so that it
    # wraps where it is counted: the typography of GLYPHS that has an ASCII
    # form becomes it (an ellipsis three dots, a dash a hyphen), the box
    # drawing and block glyphs of the Encoder stay, the letters of SPELLED
    # are spelled out, accented letters lose the accent, and anything else
    # is a question mark. ANSI escape sequences are kept.
    #
    #   BBS::Petscii.plain('Ærø – “café”…')   # => 'Aero - "cafe"...'
    def self.plain(text) = text.to_s.gsub(UNPLAIN) { |c| plain_char(c) }

    # One character as ::plain writes it.
    def self.plain_char(char)
      glyph = GLYPHS[char]
      return char if NATIVE.include?(char) || (glyph && !glyph.ascii_only?)
      return glyph if glyph

      SPELLED.fetch(char) { ascii_letter?(base(char)) ? base(char) : '?' }
    end
  end
end

require_relative 'petscii/encoder'
