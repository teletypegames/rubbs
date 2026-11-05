# frozen_string_literal: true

module Rubbs
  module Common
    module Text
      # A block font five pixels high for a board's logo: the letters A-Z, the
      # digits and some signs, most three pixels wide, a pixel of space between
      # them. A modern terminal shows it in half blocks, two pixel rows to a
      # line (::half_blocks); a Commodore 64 in reversed spaces, a pixel row to
      # a line (::petscii). A word of nine letters is 35 columns wide, so it
      # fits the C64's 40.
      #
      # A glyph is five Strings, <tt>#</tt> for a set pixel and <tt>.</tt> for
      # a clear one. Every method takes +glyphs+, a Hash of glyphs over FONT,
      # for another shape of a letter (NARROW_I, WIDE_W) or one of the board's
      # own.
      #
      #   Rubbs::Common::Text::BlockFont.half_blocks('WARP')
      #   Rubbs::Common::Text::BlockFont.petscii('SCRIPTORIUM', colors: [WH, WH, YE, YE, CY],
      #                          glyphs: Rubbs::Common::Text::BlockFont::NARROW_I)
      module BlockFont
        # The pixel rows of a glyph.
        HEIGHT = 5
        # A set pixel in a glyph row.
        SET = '#'
        # A clear pixel in a glyph row.
        CLEAR = '.'

        # The glyphs: a character => its five rows.
        FONT = {
          'A' => %w[.#. #.# ### #.# #.#],
          'B' => %w[##. #.# ##. #.# ##.],
          'C' => %w[### #.. #.. #.. ###],
          'D' => %w[##. #.# #.# #.# ##.],
          'E' => %w[### #.. ##. #.. ###],
          'F' => %w[### #.. ##. #.. #..],
          'G' => %w[### #.. #.# #.# ###],
          'H' => %w[#.# #.# ### #.# #.#],
          'I' => %w[### .#. .#. .#. ###],
          'J' => %w[..# ..# ..# #.# ###],
          'K' => %w[#.# #.# ##. #.# #.#],
          'L' => %w[#.. #.. #.. #.. ###],
          'M' => %w[#.# ### ### #.# #.#],
          'N' => %w[##. #.# #.# #.# #.#],
          'O' => %w[### #.# #.# #.# ###],
          'P' => %w[##. #.# ##. #.. #..],
          'Q' => %w[### #.# #.# ##. .##],
          'R' => %w[##. #.# ##. #.# #.#],
          'S' => %w[### #.. ### ..# ###],
          'T' => %w[### .#. .#. .#. .#.],
          'U' => %w[#.# #.# #.# #.# ###],
          'V' => %w[#.# #.# #.# #.# .#.],
          'W' => %w[#.# #.# #.# ### #.#],
          'X' => %w[#.# #.# .#. #.# #.#],
          'Y' => %w[#.# #.# .#. .#. .#.],
          'Z' => %w[### ..# .#. #.. ###],
          '0' => %w[### #.# #.# #.# ###],
          '1' => %w[.#. ##. .#. .#. ###],
          '2' => %w[### ..# ### #.. ###],
          '3' => %w[### ..# .## ..# ###],
          '4' => %w[#.# #.# ### ..# ..#],
          '5' => %w[### #.. ### ..# ###],
          '6' => %w[### #.. ### #.# ###],
          '7' => %w[### ..# ..# ..# ..#],
          '8' => %w[### #.# ### #.# ###],
          '9' => %w[### #.# ### ..# ###],
          ' ' => %w[. . . . .],
          '.' => %w[. . . . #],
          ',' => %w[. . . # #],
          '!' => %w[# # # . #],
          '?' => %w[### ..# .## ... .#.],
          '-' => %w[... ... ### ... ...],
          '+' => %w[... .#. ### .#. ...],
          ':' => %w[. # . # .],
          "'" => %w[# # . . .],
          '/' => %w[..# ..# .#. #.. #..]
        }.freeze
        # An I one pixel wide, a plain stroke.
        NARROW_I = { 'I' => %w[# # # # #] }.freeze
        # A W five pixels wide, with the middle stroke.
        WIDE_W = { 'W' => %w[#...# #...# #.#.# ##.## #...#] }.freeze

        # A pair of pixels, the upper and the lower, => its half block.
        HALF = { [true, true] => '█', [true, false] => '▀', [false, true] => '▄', [false, false] => ' ' }.freeze

        # The five rows of +char+ (looked up as it is, then in capitals) in
        # +glyphs+ over FONT. Raises KeyError for a character the font lacks.
        def self.glyph(char, glyphs: {})
          glyphs[char] || FONT[char] || glyphs[char.upcase] || FONT.fetch(char.upcase)
        end

        # The five pixel rows of +word+, its glyphs side by side with a clear
        # column between them: an Array of Strings of <tt>#</tt> and
        # <tt>.</tt>. Raises KeyError for a character the font lacks.
        #
        #   Rubbs::Common::Text::BlockFont.rows('HI').first   # => "#.#.###"
        def self.rows(word, glyphs: {})
          chars = word.to_s.chars
          Array.new(HEIGHT) { |row| chars.map { |c| glyph(c, glyphs: glyphs)[row] }.join(CLEAR) }
        end

        # The columns +word+ takes.
        def self.width(word, glyphs: {}) = rows(word, glyphs: glyphs).first.length

        # +word+ in three rows of half blocks (█ ▀ ▄ and space), the five pixel
        # rows two by two, the last with a clear row under it. Each row is as
        # wide as the word.
        #
        # [colors] an Array of SGR sequences, one a row, or one sequence for
        #          all: each row starts with its colour and ends with +reset+;
        #          +nil+ for bare rows
        # [reset]  what ends a coloured row
        #
        # Returns the rows, an Array of three Strings.
        def self.half_blocks(word, glyphs: {}, colors: nil, reset: Modern::Ansi::RESET)
          lines = pixel_pairs(rows(word, glyphs: glyphs)).map { |pairs| pairs.map { |pair| HALF[pair] }.join }
          return lines if colors.nil?

          lines.each_with_index.map { |line, i| "#{color_of(colors, i)}#{line}#{reset}" }
        end

        # The pixel +rows+ two by two, each pair of rows as the [upper, lower]
        # pixels of its columns; the fifth row pairs with a clear one.
        def self.pixel_pairs(rows)
          bits = rows.map { |r| r.chars.map { |c| c == SET } }
          bits << Array.new(bits.first.size, false)
          bits.each_slice(2).map { |top, bottom| top.zip(bottom) }
        end
        private_class_method :pixel_pairs

        # One pixel row, a String of <tt>#</tt> and <tt>.</tt> (or spaces), as
        # reversed spaces: every run of set pixels between +reverse+ and
        # +normal+, the clear ones plain spaces.
        #
        #   Rubbs::Common::Text::BlockFont.reversed('#.##')   # => "\e[7m \e[27m \e[7m  \e[27m"
        def self.reversed(row, reverse: Modern::Ansi::REVERSE, normal: Modern::Ansi::REVERSE_OFF)
          row.gsub(/#{SET}+/o) { |run| "#{reverse}#{' ' * run.size}#{normal}" }.tr(CLEAR, ' ')
        end

        # +word+ in five rows of reversed spaces (::reversed) for a C64, each
        # row +indent+ spaces in, then its colour, then the pixels, then +reset+.
        #
        # [colors] an Array of SGR sequences (Rubbs::Petscii::Colors), one a
        #          row, or one sequence for all
        # [indent] the spaces before each row
        # [reset]  what ends each row
        #
        # Returns the rows, an Array of five Strings.
        #
        #   Rubbs::Common::Text::BlockFont.petscii('WARP', colors: [LB, LB, CY, CY, WH], indent: 10)
        def self.petscii(
          word,
          colors:,
          glyphs: {},
          indent: 0,
          reset: Modern::Ansi::GREY,
          reverse: Modern::Ansi::REVERSE,
          normal: Modern::Ansi::REVERSE_OFF
        )
          rows(word, glyphs: glyphs).each_with_index.map do |row, i|
            "#{' ' * indent}#{color_of(colors, i)}#{reversed(row, reverse: reverse, normal: normal)}#{reset}"
          end
        end

        # The colour of row +index+: +colors+ itself when it is one sequence.
        def self.color_of(colors, index) = colors.is_a?(Array) ? colors[index] : colors
        private_class_method :color_of
      end
    end
  end
end
