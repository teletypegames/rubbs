# frozen_string_literal: true

module BBS
  class FrameBuffer
    # The drawing helpers of a FrameBuffer, all in 1-based coordinates:
    # filled rectangles, lines, frames with a title, drop shadows.
    module Drawing
      # Fills the rectangle at +x+, +y+ of +width+ by +height+ cells with
      # +char+ in style +sgr+.
      def fill(x:, y:, width:, height:, sgr: nil, char: ' ')
        height.times { |r| hline(x: x, y: y + r, length: width, char: char, sgr: sgr) }
      end

      # Draws a horizontal line of +length+ +char+ characters from +x+, +y+
      # in style +sgr+.
      def hline(x:, y:, length:, char: '─', sgr: nil)
        move(x, y)
        write(char * [length, 0].max, sgr: sgr)
      end

      # Draws a vertical line of +length+ +char+ characters down from +x+, +y+
      # in style +sgr+.
      def vline(x:, y:, length:, char: '│', sgr: nil)
        length.times do |r|
          move(x, y + r)
          write(char, sgr: sgr)
        end
      end

      # Draws a frame of +width+ by +height+ cells with its top left at +x+,
      # +y+. Does nothing when either side is under 2.
      #
      # [sgr]          style of the frame
      # [fill_sgr]     when given, the inside is cleared with spaces in this style
      # [style]        a BOX_CHARS key; an unknown one draws +:single+
      # [title]        text set into the top edge, clipped to fit
      # [title_sgr]    style of the title (defaults to +sgr+)
      # [title_indent] edge characters drawn before the title
      def box(
        x:,
        y:,
        width:,
        height:,
        sgr: nil,
        fill_sgr: nil,
        style: :single,
        title: nil,
        title_sgr: nil,
        title_indent: 0
      )
        return if width < 2 || height < 2

        edge = Edge.new(x, width, BOX_CHARS[style] || BOX_CHARS[:single], sgr)
        top_edge(edge, y, title.to_s, title_sgr || sgr, [title_indent, 0].max)
        (1...(height - 1)).each { |r| box_side(edge, y + r, fill_sgr) }
        edge_row(edge, y + height - 1, :bl, :br)
      end

      # Draws the drop shadow of a +width+ by +height+ rectangle at +x+, +y+:
      # two columns down its right side and one row under it, offset by one
      # row and two columns, in style +sgr+ (black background by default).
      def shadow(x:, y:, width:, height:, sgr: nil)
        sgr ||= Ansi::BG_BLACK
        height.times { |r| hline(x: x + width, y: y + 1 + r, length: 2, char: ' ', sgr: sgr) } if x + width < @cols
        hline(x: x + 2, y: y + height, length: width, char: ' ', sgr: sgr) if y + height <= @rows
      end

      private

      # One box being drawn: its left column +x+, its +width+, its +chars+
      # (a BOX_CHARS entry) and the style +sgr+ of its frame.
      Edge = Struct.new(:x, :width, :chars, :sgr) do
        # The character of +part+ (+:tl+, +:h+ …).
        def [](part) = chars[part]

        # The room for a title after +indent+ edge characters.
        def title_room(indent) = [width - 4 - indent, 0].max

        # The end of a top edge: +count+ edge characters and the corner.
        def rest(count) = "#{chars[:h] * count}#{chars[:tr]}"
      end
      private_constant :Edge

      # A row of a box's frame from corner +left+ to corner +right+.
      def edge_row(edge, y, left, right)
        g = edge.chars
        hline(x: edge.x, y: y, length: 1, char: g[left], sgr: edge.sgr)
        write(g[:h] * (edge.width - 2), sgr: edge.sgr)
        write(g[right], sgr: edge.sgr)
      end

      # The top edge of a box, with the +title+ (when there is one) after
      # +indent+ edge characters.
      def top_edge(edge, y, title, title_sgr, indent)
        return edge_row(edge, y, :tl, :tr) if title.empty?

        room    = edge.title_room(indent)
        clipped = title[0, room]
        move(edge.x, y)
        write("#{edge[:tl]}#{edge[:h] * (indent + 1)} ", sgr: edge.sgr)
        write(clipped, sgr: title_sgr)
        write(edge.rest(room - clipped.length), sgr: edge.sgr)
      end

      # One row of a box's sides, its inside cleared with +fill_sgr+.
      def box_side(edge, y, fill_sgr)
        hline(x: edge.x, y: y, length: 1, char: edge.chars[:v], sgr: edge.sgr)
        write(' ' * (edge.width - 2), sgr: fill_sgr) if fill_sgr
        hline(x: edge.x + edge.width - 1, y: y, length: 1, char: edge.chars[:v], sgr: edge.sgr)
      end
    end

    include Drawing
  end
end
