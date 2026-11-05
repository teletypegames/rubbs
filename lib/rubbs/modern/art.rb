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
