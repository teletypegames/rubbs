# frozen_string_literal: true

module BBS
  module Petscii
    class Canvas
      # The bytes that send a Canvas to a C64: the whole screen (#frame),
      # a stretch of a row (#span), scattered cells (#patch), the cursor
      # alone (#cursor). Each is raw PETSCII, a binary String for
      # <tt>session.write_raw</tt>.
      module Output
        # The whole screen: the graphics set, a clear screen, then the rows,
        # each cut after its last visible cell, as a binary String.
        def frame
          out  = [UPPERCASE, CLEAR]
          pen  = Pen.new
          last = last_visible_row
          (0..last).each do |row|
            len = visible_end(row)
            pen.emit(out, @cells[row].first(len))
            next if len == COLS || row == last

            out << CR
            pen.rvs = false
          end
          out.pack('C*')
        end

        # The cells of +row+ from +col+, +width+ long, with the cursor moves
        # that put them in place, as a binary String.
        def span(row, col, width)
          out = moves_to(row, col) << RVS_OFF
          pen = Pen.new
          pen.emit(out, @cells[row][col, width])
          pen.close(out).pack('C*')
        end

        # The cells at +positions+, [row, col] each, the cursor stepping to
        # the nearest one left instead of from the top left each time: the
        # cheap repaint of a few cells scattered over the screen. A binary
        # String.
        def patch(positions)
          out = [HOME, RVS_OFF]
          pen = Pen.new
          at  = [0, 0]
          nearest_first(positions.uniq).each do |row, col|
            at = step_to(out, at, row, col)
            pen.emit(out, [@cells[row][col]])
          end
          pen.close(out).pack('C*')
        end

        # The cursor moves to +row+, +col+, with nothing printed: HOME, then
        # down and right. A binary String.
        def cursor(row, col) = moves_to(row, col).pack('C*')

        private

        # The colour and reverse video sent so far while cells go out.
        class Pen
          # Whether reverse video is on.
          attr_accessor :rvs

          # A pen with no colour sent and reverse video off.
          def initialize
            @color = nil
            @rvs   = false
          end

          # Appends the codes of +cells+ to +out+, with the colour and RVS
          # codes each needs: an invisible cell takes no colour.
          def emit(out, cells)
            cells.each do |cell|
              visible = cell.visible?
              color(out, cell.color) if visible && cell.color
              reverse(out, cell.rvs) if visible || @rvs
              out << cell.code
            end
          end

          # Turns reverse video off at the end of +out+ when it is on.
          # Returns +out+.
          def close(out)
            out << RVS_OFF if @rvs
            out
          end

          private

          def color(out, code)
            return if code == @color

            out << code
            @color = code
          end

          def reverse(out, rvs)
            return if rvs == @rvs

            out << (rvs ? RVS_ON : RVS_OFF)
            @rvs = rvs
          end
        end

        private_constant :Pen

        def moves_to(row, col) = [HOME] + ([DOWN] * row) + ([RIGHT] * col)

        # +positions+ in the order the cursor visits them, each time the
        # nearest one left.
        def nearest_first(positions)
          at = [0, 0]
          left = positions.dup
          Array.new(positions.size) do
            row, col = left.min_by { |r, c| [distance(at, r, c), r, c] }
            left.delete([row, col])
            at = after(row, col)
            [row, col]
          end
        end

        # Moves the cursor from +at+ to +row+, +col+ (from HOME when that
        # is nearer) and returns where it is after printing a cell there.
        def step_to(out, at, row, col)
          if row + col < distance(at, row, col)
            out << HOME
            at = [0, 0]
          end
          out.concat(steps(at, row, col))
          after(row, col)
        end

        def after(row, col) = col == COLS - 1 ? [row + 1, 0] : [row, col + 1]

        def distance(from, row, col) = (row - from[0]).abs + (col - from[1]).abs

        def steps(from, row, col)
          dr = row - from[0]
          dc = col - from[1]
          (dr.negative? ? [UP] * -dr : [DOWN] * dr) + (dc.negative? ? [LEFT] * -dc : [RIGHT] * dc)
        end

        def last_visible_row
          last = ROWS - 1
          last -= 1 while last.positive? && visible_end(last).zero?
          last
        end

        def visible_end(row)
          cells = @cells[row]
          len = cells.size
          len -= 1 while len.positive? && !cells[len - 1].visible?
          len
        end
      end

      include Output
    end
  end
end
