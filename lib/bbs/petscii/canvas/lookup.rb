# frozen_string_literal: true

module BBS
  module Petscii
    class Canvas
      # The class methods of a Canvas that look codes up: the code of a
      # character (Canvas.code), whether the set has a glyph for it
      # (Canvas.glyph?), the code of a colour (Canvas.color) and the
      # nearest C64 colour to an RGB one (Canvas.nearest).
      module Lookup
        # The PETSCII code of +ch+ in the uppercase set, and whether it is a
        # reversed glyph (GLYPHS_REVERSED): <tt>[code, reversed]</tt>. A
        # character the set does not have is <tt>'?'</tt>.
        def code(ch)
          return [GLYPHS_REVERSED[ch], true] if GLYPHS_REVERSED.key?(ch)
          return [GLYPHS[ch], false] if GLYPHS.key?(ch)

          o = ch.upcase.ord
          o.between?(0x20, 0x5d) ? [o, false] : ['?'.ord, false]
        end

        # Whether the uppercase set shows +ch+ as what it is: a glyph of
        # GLYPHS or GLYPHS_REVERSED, or printable ASCII but the backslash (a
        # lowercase letter shows as its capital).
        def glyph?(ch)
          return true if GLYPHS.key?(ch) || GLYPHS_REVERSED.key?(ch)

          ch.length == 1 && ASCII_SHOWN.include?(ch.upcase.ord)
        end

        # The colour code of +color+: a code as it is (a key of RGB), an SGR
        # colour of the palette (BBS::Petscii::Colors), a name
        # of COLOR_NAMES as a Symbol or String (<tt>'light grey'</tt>,
        # <tt>:dark_gray</tt> and <tt>'LIGHT-BLUE'</tt> all work), or +nil+.
        # Raises ArgumentError for anything else.
        def color(color)
          return nil if color.nil?
          return color if color.is_a?(Integer) && RGB.key?(color)
          return Petscii.color_code(color) if color.to_s.start_with?(Ansi::ESC)

          name = color.to_s.downcase.tr(' -', '__').sub('gray', 'grey').to_sym
          COLOR_NAMES.fetch(name) { raise ArgumentError, "not a C64 colour: #{color.inspect}" }
        end

        # The code of the C64 colour nearest to +rgb+, [red, green, blue].
        def nearest(rgb) = RGB.min_by { |_, c| c.zip(rgb).sum { |a, b| (a - b)**2 } }.first
      end

      extend Lookup
    end
  end
end
