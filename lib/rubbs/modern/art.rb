# frozen_string_literal: true

module Rubbs
  module Modern
    # A drawing (Rubbs::Common::Art) on a modern terminal: as lines of
    # 256-colour ANSI, or on a FrameBuffer.
    #
    #   session.write(Rubbs::Modern::Art.text(art))
    #   Rubbs::Modern::Art.draw(art, frame, x: 3, y: 2)
    module Art
      module_function

      # +art+ as lines of 256-colour ANSI: each line starts with its own
      # colours and ends with a reset, so a line can be written anywhere.
      def lines(art)
        art.grid.map do |row|
          line = +''
          sgr  = nil
          row.each do |cell|
            s = Common::Art.sgr(cell)
            line << s if s != sgr
            sgr = s
            line << cell.char
          end
          line << Ansi::RESET
        end
      end

      # The #lines of +art+ joined with CR LF, for writing at the start of a
      # line.
      def text(art) = lines(art).join(Ansi::CRLF)

      # Draws +art+ on +frame+, a FrameBuffer, with its top left at +x+, +y+
      # (1-based), cut to +width+ × +height+ cells (default the whole art)
      # and to the buffer. A cell with no colours gets no style.
      #
      # Returns +frame+.
      def draw(art, frame, x: 1, y: 1, width: art.cols, height: art.rows)
        [height, art.rows].min.times do |r|
          [width, art.cols].min.times { |c| put(frame, art.grid[r][c], x + c, y + r) }
        end
        frame
      end

      # Writes +art+ on the screen of +session+ outside an Application, its
      # top left at +top+, +left+ (1-based): each line placed with a cursor
      # move, so the art stands on whatever is around it. Returns +nil+.
      #
      #   Rubbs::Modern::Art.draw_on(art, session, top: 2)
      #   Rubbs::Modern::Art.write(art, session, :ticket, 'COAT CHECK', sgr: Style[fg: 236, bg: 223], line: 1, top: 2)
      def draw_on(art, session, top: 1, left: 1)
        session.write(lines(art).each_with_index.map { |line, i| "#{Ansi.move(top + i, left)}#{line}" }.join)
        nil
      end

      # Writes +text+ in the hotspot +name+ of +art+ drawn at +top+, +left+
      # by #draw_on: on its row +line+ (0-based), in style +sgr+, cut or
      # padded to the hotspot's width and placed by +align+ (+:left+,
      # +:center+ or +:right+). A +line+ below the hotspot writes nothing.
      # Raises what Rubbs::Common::Art#hotspot raises for an unknown name.
      # Returns +nil+.
      def write(art, session, name, text, sgr: nil, line: 0, align: :left, top: 1, left: 1)
        spot = art.hotspot(name)
        return nil if line >= spot.height

        session.write("#{Ansi.move(top + spot.row + line, left + spot.col)}#{sgr}#{fit(text, spot.width, align)}#{Ansi::RESET}")
        nil
      end

      # +text+ (plain) cut or padded to +width+ cells, placed by +align+.
      def fit(text, width, align)
        text = FrameBuffer.plain(text.to_s)[0, width]
        case align
        when :center then text.center(width)
        when :right then text.rjust(width)
        else text.ljust(width)
        end
      end

      # Writes +cell+ at +x+, +y+ of +frame+; a cell with no colours gets no
      # style.
      def put(frame, cell, x, y)
        plain = cell.fg.nil? && cell.bg.nil? && !cell.rvs
        frame.move(x, y)
        frame.write(cell.char, sgr: plain ? nil : Common::Art.sgr(cell))
      end
    end
  end
end
