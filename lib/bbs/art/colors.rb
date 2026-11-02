# frozen_string_literal: true

module BBS
  class Art
    # The class methods of an Art for its colours: a palette entry as a
    # Color (Art.color), the xterm 256-colour index of an RGB colour
    # (Art.ansi256) and back (Art.rgb256), and the SGR of a cell (Art.sgr).
    module Colors
      # The Color of +value+, a palette entry: a C64 colour name, a 256-colour
      # index or <tt>#rrggbb</tt>. Raises ArgumentError for anything else.
      def color(value)
        case value
        when Integer
          raise ArgumentError, "a 256-colour index is 0-255, not #{value}" unless value.between?(0, 255)

          Color.new(Petscii::Canvas.nearest(rgb256(value)), value)
        when /\A#\h{6}\z/
          rgb = value[1..].scan(/../).map(&:hex)
          Color.new(Petscii::Canvas.nearest(rgb), ansi256(rgb))
        else
          c64 = Petscii::Canvas.color(value)
          Color.new(c64, ansi256(Petscii::Canvas::RGB[c64]))
        end
      end

      # The xterm 256-colour index nearest to +rgb+, [red, green, blue], from
      # the colour cube and the grey ramp (16-255: the first sixteen differ
      # from terminal to terminal).
      def ansi256(rgb) = (16..255).min_by { |i| rgb256(i).zip(rgb).sum { |a, b| (a - b)**2 } }

      # The [red, green, blue] of xterm 256-colour index +index+ (the first
      # sixteen as xterm's defaults).
      def rgb256(index)
        return SYSTEM_RGB[index] if index < 16
        return [8 + ((index - 232) * 10)] * 3 if index >= 232

        i = index - 16
        [CUBE[i / 36], CUBE[(i / 6) % 6], CUBE[i % 6]]
      end

      # The default colours of xterm's first sixteen indexes.
      SYSTEM_RGB = [[0, 0, 0], [205, 0, 0], [0, 205, 0], [205, 205, 0], [0, 0, 238], [205, 0, 205], [0, 205, 205],
                    [229, 229, 229], [127, 127, 127], [255, 0, 0], [0, 255, 0], [255, 255, 0], [92, 92, 255],
                    [255, 0, 255], [0, 255, 255], [255, 255, 255]].freeze

      # The SGR sequence of +cell+: a reset, then its 256-colour foreground
      # and background and reverse video.
      def sgr(cell)
        parts = ['0']
        parts << "38;5;#{cell.fg.ansi}" if cell.fg
        parts << "48;5;#{cell.bg.ansi}" if cell.bg
        parts << '7' if cell.rvs
        "\e[#{parts.join(';')}m"
      end
    end

    extend Colors
  end
end
