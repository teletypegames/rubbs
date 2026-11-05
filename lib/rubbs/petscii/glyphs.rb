# frozen_string_literal: true

module Rubbs
  module Petscii
    # The glyph table: the graphics of the C64 by the Unicode character
    # they look like, as PETSCII codes, the look-alikes and the ASCII forms
    # of what the C64 has no glyph for. The Encoder writes by GLYPHS, the
    # Canvas draws by GRAPHICS and UPPERCASE_GRAPHICS.
    module Glyphs
      # The graphics of the C64 by the Unicode character they look like, as
      # PETSCII codes. The lowercase set (the Encoder's) and the
      # uppercase/graphics set (Rubbs::Petscii::Canvas) share most of them.

      # Graphics both character sets have at the same code: the box drawing
      # with square corners, the blocks, £ ↑ ←.
      GRAPHICS = {
        '─' => 0xc0,
        '│' => 0xdd,
        '┼' => 0xdb,
        '┌' => 0xb0,
        '┐' => 0xae,
        '└' => 0xad,
        '┘' => 0xbd,
        '├' => 0xab,
        '┤' => 0xb3,
        '┬' => 0xb2,
        '┴' => 0xb1,
        '▌' => 0xa1,
        '▄' => 0xa2,
        '▔' => 0xa3,
        '▁' => 0xa4,
        '▒' => 0xa6,
        '▖' => 0xbb,
        '▗' => 0xac,
        '▘' => 0xbe,
        '▝' => 0xbc,
        '▚' => 0xbf,
        '£' => 0x5c,
        '↑' => 0x5e,
        '←' => 0x5f
      }.freeze
      # The rounded corners, which only the uppercase/graphics set has; the
      # lowercase set draws them as the square ones (LOOK_ALIKES).
      ROUNDED_CORNERS = { '╭' => 0xd5, '╮' => 0xc9, '╰' => 0xca, '╯' => 0xcb }.freeze
      # The graphics only the uppercase/graphics set has: the rounded
      # corners, the balls, the card suits, the diagonals.
      UPPERCASE_GRAPHICS = ROUNDED_CORNERS.merge(
        '●' => 0xd1,
        '○' => 0xd7,
        '♥' => 0xd3,
        '♠' => 0xc1,
        '♣' => 0xd8,
        '♦' => 0xda,
        'π' => 0xde,
        '╲' => 0xcd,
        '╱' => 0xce,
        '╳' => 0xd6,
        '◤' => 0xa9,
        '◥' => 0xdf
      ).freeze
      # The graphics only the lowercase set has: the tick.
      LOWERCASE_GRAPHICS = { '✓' => 0xba, '✔' => 0xba }.freeze
      # Characters the lowercase set shows as the graphic of a look-alike:
      # double and heavy lines as single ones, rounded corners as square ones.
      LOOK_ALIKES = {
        '━' => '─',
        '═' => '─',
        '┃' => '│',
        '║' => '│',
        '|' => '│',
        '╔' => '┌',
        '╭' => '┌',
        '╗' => '┐',
        '╮' => '┐',
        '╚' => '└',
        '╰' => '└',
        '╝' => '┘',
        '╯' => '┘',
        '╠' => '├',
        '╣' => '┤',
        '╦' => '┬',
        '╩' => '┴',
        '╬' => '┼',
        '░' => '▒',
        '▓' => '▒',
        '_' => '▁',
        '^' => '↑'
      }.freeze
      # The typography of a modern board in ASCII, for the characters the C64
      # has no glyph for.
      ASCII_FORMS = {
        '\\' => '/',
        '`'  => "'",
        '{'  => '(',
        '}'  => ')',
        '~'  => '-',
        '–'  => '-',
        '—'  => '-',
        '―'  => '-',
        '‘'  => "'",
        '’'  => "'",
        '“'  => '"',
        '”'  => '"',
        '„'  => '"',
        '…'  => '...',
        '·'  => '.',
        '•'  => '*',
        '●'  => '*',
        '◆'  => '*',
        '★'  => '*',
        '■'  => '*',
        '☼'  => '*',
        '○'  => 'o',
        '◄'  => '<',
        '◀'  => '<',
        '‹'  => '<',
        '«'  => '<',
        '►'  => '>',
        '▶'  => '>',
        '▸'  => '>',
        '›'  => '>',
        '»'  => '>',
        '→'  => '>',
        '↓'  => 'v',
        '×'  => 'x',
        '°'  => 'o',
        '≈'  => '-',
        '∿'  => '-',
        '≋'  => '-',
        ' '  => ' ',
        'ß'  => 'ss',
        'π'  => 'pi'
      }.freeze
      # What the Encoder writes for a character of the lowercase set: the
      # PETSCII code point of its graphic (GRAPHICS, LOWERCASE_GRAPHICS,
      # LOOK_ALIKES), or its ASCII form.
      GLYPHS = GRAPHICS.merge(LOWERCASE_GRAPHICS)
        .then { |codes| codes.merge(LOOK_ALIKES.transform_values { |c| codes.fetch(c) }) }
        .transform_values { |code| code.chr(Encoding::UTF_8) }
        .merge(ASCII_FORMS).freeze
    end
  end
end
