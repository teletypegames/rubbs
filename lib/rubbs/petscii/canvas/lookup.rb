# frozen_string_literal: true

module Rubbs
  module Petscii
    class Canvas
      # The class methods of a Canvas that look codes up: the code of a
      # character (Canvas.code), whether the set has a glyph for it
      # (Canvas.glyph?), the character a code looks like (Canvas.look),
      # text made of what a set shows (Canvas.plain), the code of a colour
      # (Canvas.color) and the nearest C64 colour to an RGB one
      # (Canvas.nearest).
      #
      # +charset+ is +:upper+ (the uppercase/graphics set, the default) or
      # +:lower+ (the lower/upper set, where a lowercase letter is 0x41-0x5a
      # and a capital 0xc1-0xda).
      module Lookup
        # The PETSCII code of +ch+ in +charset+, and whether it is a reversed
        # glyph (GLYPHS_REVERSED, LOWER_GLYPHS_REVERSED): <tt>[code,
        # reversed]</tt>. A character the set does not have is
        # <tt>'?'</tt>; in the uppercase set a lowercase letter is its
        # capital.
        def code(ch, charset = :upper)
          return lower_code(ch) if charset == :lower
          return [GLYPHS_REVERSED[ch], true] if GLYPHS_REVERSED.key?(ch)
          return [GLYPHS[ch], false] if GLYPHS.key?(ch)

          o = ch.upcase.ord
          o.between?(0x20, 0x5d) ? [o, false] : ['?'.ord, false]
        end

        # Whether +charset+ shows +ch+ as what it is: a glyph of the set
        # (GLYPHS and GLYPHS_REVERSED, or LOWER_GLYPHS and
        # LOWER_GLYPHS_REVERSED), or printable ASCII but the backslash (in
        # the uppercase set a lowercase letter shows as its capital).
        def glyph?(ch, charset = :upper)
          return lower_glyph?(ch) if charset == :lower
          return true if GLYPHS.key?(ch) || GLYPHS_REVERSED.key?(ch)

          ch.length == 1 && ASCII_SHOWN.include?(ch.upcase.ord)
        end

        # The Unicode character the PETSCII +code+ looks like in +charset+,
        # <tt>'?'</tt> for one with no look-alike: the reverse of ::code.
        def look(code, charset = :upper)
          return lower_look(code) if charset == :lower

          UPPER_LOOKS[code] || (code < 0x80 ? code.chr : '?')
        end

        # +text+ in the characters +charset+ shows (::glyph?): another
        # character becomes its plain look-alike (Rubbs::Petscii.plain) when
        # the set has that, else <tt>'?'</tt>.
        #
        #   Rubbs::Petscii::Canvas.plain('Café “Ö”', :lower)   # => 'Cafe "O"'
        def plain(text, charset = :upper)
          text.to_s.each_char.map do |c|
            next c if glyph?(c, charset)

            near = Petscii.plain(c)
            near.each_char.all? { |n| glyph?(n, charset) } ? near : '?'
          end.join
        end

        # The colour code of +color+: a code as it is (a key of RGB), an SGR
        # colour of the palette (Rubbs::Petscii::Colors), a name
        # of COLOR_NAMES as a Symbol or String (<tt>'light grey'</tt>,
        # <tt>:dark_gray</tt> and <tt>'LIGHT-BLUE'</tt> all work), or +nil+.
        # Raises ArgumentError for anything else.
        def color(color)
          return nil if color.nil?
          return color if color.is_a?(Integer) && RGB.key?(color)
          return Petscii.color_code(color) if color.to_s.start_with?(Modern::Ansi::ESC)

          name = color.to_s.downcase.tr(' -', '__').sub('gray', 'grey').to_sym
          COLOR_NAMES.fetch(name) { raise ArgumentError, "not a C64 colour: #{color.inspect}" }
        end

        # The code of the C64 colour nearest to +rgb+, [red, green, blue].
        def nearest(rgb) = RGB.min_by { |_, c| c.zip(rgb).sum { |a, b| (a - b)**2 } }.first

        private

        def lower_code(ch)
          return [LOWER_GLYPHS_REVERSED[ch], true] if LOWER_GLYPHS_REVERSED.key?(ch)
          return [LOWER_GLYPHS[ch], false] if LOWER_GLYPHS.key?(ch)

          [lower_letter(ch) || (ASCII_SHOWN.include?(ch.ord) ? ch.ord : '?'.ord), false]
        end

        # The code of the letter +ch+ in the lower/upper set, +nil+ for
        # another character.
        def lower_letter(ch)
          return nil unless ch.length == 1

          if ch.between?('a', 'z') then ch.ord - 0x20
          elsif ch.between?('A', 'Z') then ch.ord + 0x80
          end
        end

        def lower_glyph?(ch)
          return true if LOWER_GLYPHS.key?(ch) || LOWER_GLYPHS_REVERSED.key?(ch)

          ch.length == 1 && (ch.between?('a', 'z') || ASCII_SHOWN.include?(ch.ord))
        end

        def lower_look(code)
          return LOWER_LOOKS[code] if LOWER_LOOKS.key?(code)
          return (code + 0x20).chr if code.between?(0x41, 0x5a)
          return (code - 0x80).chr if code.between?(0xc1, 0xda)

          code < 0x80 ? code.chr : '?'
        end
      end

      # The character each graphic of the uppercase set looks like, by code.
      UPPER_LOOKS = GLYPHS.invert.freeze
      # The character each graphic of the lower/upper set looks like, by
      # code (a space a space).
      LOWER_LOOKS = LOWER_GLYPHS.invert.merge(SPACE => ' ').freeze
      private_constant :UPPER_LOOKS, :LOWER_LOOKS

      extend Lookup
    end
  end
end
