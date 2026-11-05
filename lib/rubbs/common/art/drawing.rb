# frozen_string_literal: true

module Rubbs
  module Common
    class Art
      # How an Art is drawn: as ANSI lines, on a Rubbs::Modern::FrameBuffer, on a
      # Rubbs::Petscii::Canvas, as a whole PETSCII screen.
      module Drawing
        # The art as lines of 256-colour ANSI: each line starts with its own
        # colours and ends with a reset, so a line can be written anywhere.
        def ansi_lines
          @grid.map do |row|
            line = +''
            sgr  = nil
            row.each do |cell|
              s = Art.sgr(cell)
              line << s if s != sgr
              sgr = s
              line << cell.char
            end
            line << Modern::Ansi::RESET
          end
        end

        # The #ansi_lines joined with CR LF, for writing at the start of a line.
        def ansi = ansi_lines.join(Modern::Ansi::CRLF)

        # Draws the art on +frame+, a Rubbs::Modern::FrameBuffer, with its top left at
        # +x+, +y+ (1-based), cut to +width+ × +height+ cells (default the
        # whole art) and to the buffer. A cell with no colours gets no style.
        #
        # Returns +frame+.
        def draw(frame, x: 1, y: 1, width: @cols, height: @rows)
          [height, @rows].min.times do |r|
            [width, @cols].min.times do |c|
              cell = @grid[r][c]
              plain = cell.fg.nil? && cell.bg.nil? && !cell.rvs
              frame.move(x + c, y + r)
              frame.write(cell.char, sgr: plain ? nil : Art.sgr(cell))
            end
          end
          frame
        end

        # Draws the art on +canvas+, a Rubbs::Petscii::Canvas, with its top left
        # at +row+, +col+ (0-based); cells off the screen are cut. A visible
        # cell with no colour is light grey, the C64's text colour. Raises
        # ArgumentError for a cp437 art.
        #
        # Returns +canvas+.
        def draw_canvas(canvas, row: 0, col: 0)
          raise ArgumentError, "#{@path}: a #{@charset} art does not go on a C64 canvas" unless petscii?

          @grid.each_with_index do |cells, r|
            cells.each_with_index do |cell, c|
              code, reversed = Petscii::Canvas.code(cell.char)
              color = cell.fg ? cell.fg.c64 : Petscii::Canvas::LIGHT_GREY
              canvas.put(row + r, col + c, code, color, rvs: cell.rvs ^ reversed)
            end
          end
          canvas
        end

        # A new Rubbs::Petscii::Canvas with the art drawn at its top left.
        def canvas = draw_canvas(Petscii::Canvas.new)

        # The raw PETSCII of the whole screen with the art on it (the #canvas's
        # +frame+), a binary String to send with <tt>session.write_raw</tt>.
        def petscii = canvas.frame
      end

      include Drawing
    end
  end
end
