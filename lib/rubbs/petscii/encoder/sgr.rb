# frozen_string_literal: true

module Rubbs
  module Petscii
    class Encoder
      # The SGR colours and reverse video of an Encoder: the pen they set,
      # turned into the C64's colour and RVS codes.
      module Sgr
        # The pen each SGR attribute parameter sets: reset (0), bold (1),
        # dim (2), reverse (7), normal intensity (22), reverse off (27) and
        # the default colour (39).
        SGR_PENS = {
          0  => { bold: false, dim: false, fg: nil, rvs: false },
          1  => { bold: true },
          2  => { dim: true },
          7  => { rvs: true },
          22 => { bold: false, dim: false },
          27 => { rvs: false },
          39 => { fg: nil }
        }.freeze
        # SGR parameters of the normal foreground colours.
        SGR_FG = 30..37
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

        private

        def sgr(codes, out)
          pen = @pen.merge(rvs: @rvs)
          each_sgr(codes) { |code| pen_code(pen, code) }
          @pen = pen.except(:rvs)
          reverse(pen[:rvs], out)
          recolor(out)
        end

        # Yields each SGR parameter of +codes+ but the arguments of an
        # extended colour.
        def each_sgr(codes)
          i = 0
          while i < codes.size
            yield codes[i]
            i += extended_length(codes, i)
          end
        end

        def extended_length(codes, index)
          return 1 unless SGR_EXTENDED.include?(codes[index])

          codes[index + 1] == SGR_INDEXED ? 3 : 5
        end

        def pen_code(pen, code)
          pen.merge!(SGR_PENS.fetch(code, {}))
          pen[:fg] = [code - SGR_FG.first, false] if SGR_FG.cover?(code)
          pen[:fg] = [code - SGR_FG_BRIGHT.first, true] if SGR_FG_BRIGHT.cover?(code)
        end

        def reverse(rvs, out)
          return if rvs == @rvs

          out << bytes(rvs ? RVS_ON : RVS_OFF)
          @rvs = rvs
        end

        def recolor(out)
          color = current_color
          return if color == @color

          out << bytes(color)
          @color = color
        end

        def current_color
          return DEFAULT if @pen == PLAIN_PEN
          return GREY if dim_white?

          index, bright = @pen[:fg] || [ANSI_WHITE, false]
          (bright || @pen[:bold] ? ANSI_BRIGHT : ANSI_DARK)[index]
        end

        def dim_white? = @pen[:dim] && (@pen[:fg].nil? || @pen[:fg].first == ANSI_WHITE)
      end

      include Sgr
    end
  end
end
