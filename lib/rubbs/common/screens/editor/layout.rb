# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      class Editor
        # The screen rows of a text wrapped at word boundaries: each row is
        # <tt>[line, start, stop]</tt>, the characters <tt>start...stop</tt> of
        # line +line+. A row breaks after the last space that fits, or at the
        # width when a word is longer than a row; it may end in one space
        # beyond the width, which takes no room.
        class Layout
          # The rows, an Array of <tt>[line, start, stop]</tt>.
          attr_reader :rows

          # Lays +lines+ (an Array of String) out in rows +width+ wide.
          def initialize(lines, width)
            @width = width
            @rows  = lines.each_with_index.flat_map do |text, i|
              starts = starts(text)
              starts.each_with_index.map { |s, j| [i, s, starts[j + 1] || text.length] }
            end
          end

          # The index of the row the cursor at +line+, +pos+ is on.
          def row_of(line, pos) = @rows.rindex { |l, start, _| l == line && start <= pos } || 0

          # The last cursor position on row +index+: its end on the last row of
          # a line, before its last character otherwise, as that position is
          # the next row's start.
          def row_end(index)
            line, start, stop = @rows[index]
            following = @rows[index + 1]
            following.nil? || following[0] != line ? stop : [stop - 1, start].max
          end

          private

          # Where the rows of +text+ start.
          def starts(text)
            starts = [0]
            pos    = 0
            while text.length - pos > @width
              space = text.rindex(' ', pos + @width)
              pos   = space && space >= pos ? space + 1 : pos + @width
              starts << pos
            end
            starts
          end
        end
      end
    end
  end
end
