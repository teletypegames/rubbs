# frozen_string_literal: true

module BBS
  module Petscii
    class Canvas
      # The bytes that send a Canvas to a C64: the whole screen (#frame),
      # a stretch of a row (#span), scattered cells (#patch), what changed
      # since another Canvas (#update, #diff), the cursor alone (#cursor). Each is raw PETSCII, a binary String for
      # <tt>session.write_raw</tt>.
      module Output
        # The whole screen: the switch to its character set (UPPERCASE or
        # LOWERCASE, see Canvas#charset), a clear screen, then the rows, each
        # cut after its last visible cell, as a binary String.
        def frame
          out  = [@charset == :lower ? LOWERCASE : UPPERCASE, CLEAR]
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

        # The cells at +positions+, [row, col] each, as a binary String.
        #
        # [order] the order the cursor visits them in: +:nearest+ (the
        #         default) steps to the nearest one left each time, the
        #         cheap repaint of a few cells scattered over the screen;
        #         +:rows+ goes row by row from the top, stepping right over
        #         the cells that stay, the cheap repaint of blocks of text
        #         (see #diff). Either way the cursor goes from HOME when
        #         that is the shorter way.
        def patch(positions, order: :nearest)
          out = [HOME, RVS_OFF]
          pen = Pen.new
          at  = [0, 0]
          visit_order(positions.uniq, order).each do |row, col|
            at = step_to(out, at, row, col)
            pen.emit(out, [@cells[row][col]])
          end
          pen.close(out).pack('C*')
        end

        # The bytes that turn +before+ (another Canvas, what the caller sees)
        # into this screen: a #patch of the #changes, or the whole #frame when
        # that is shorter; an empty String when nothing changed.
        def update(before) = cheaper(changes(before), :nearest)

        # The bytes that turn +before+ (another Canvas, what the caller sees)
        # into this screen, for a screen of text: a #patch of the #changes in
        # <tt>order: :rows</tt>, or the whole #frame when that is shorter; an
        # empty String when nothing changed. Cheaper than #update when blocks
        # of text change (a list's lit row, a page turned).
        #
        #   session.write_raw(canvas.diff(shown))
        def diff(before) = cheaper(changes(before), :rows)

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

        def cheaper(changed, order)
          return ''.b if changed.empty?

          cheap = patch(changed, order: order)
          whole = frame
          cheap.bytesize <= whole.bytesize ? cheap : whole
        end

        def moves_to(row, col) = [HOME] + ([DOWN] * row) + ([RIGHT] * col)

        def visit_order(positions, order)
          case order
          when :nearest then nearest_first(positions)
          when :rows then positions.sort
          else raise ArgumentError, "not an order: #{order.inspect}"
          end
        end

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
