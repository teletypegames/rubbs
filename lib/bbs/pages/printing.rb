# frozen_string_literal: true

module BBS
  class Pages
    # Drawing helpers of a BBS::Page and of a BBS::Pages runner (for the
    # frame it draws around the page).
    module Printing
      # Writes +lines+ of ANSI text (colours kept, see
      # BBS::FrameBuffer#write_ansi) into the BBS::FrameBuffer +frame+, one a
      # row from column +x+, row +y+ (1-based), at most +limit+ of them
      # (default: down to the bottom of the frame). With +clear+ each row is
      # blanked from +x+ to its end first, so a line drawn over another (a
      # prompt over a page) leaves nothing of it. Returns the row after the
      # last one written.
      def print_lines(frame, lines, x: 1, y: 1, limit: nil, clear: false)
        shown = lines.first(limit || [frame.rows - y + 1, 0].max)
        shown.each_with_index do |line, i|
          blank_row(frame, x, y + i) if clear
          frame.move(x, y + i)
          frame.write_ansi(line.to_s)
        end
        y + shown.size
      end

      private

      # Blanks +row+ of +frame+ from column +x+ to its end.
      def blank_row(frame, x, row)
        frame.move(x, row)
        frame.write(' ' * [frame.cols - x + 1, 0].max)
      end
    end
  end
end
