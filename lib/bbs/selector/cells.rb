# frozen_string_literal: true

module BBS
  class Selector
    # What a Selector shows, as segments: <tt>[text, colour, reversed]</tt>,
    # the colour a role of Selector::COLORS or an item's own. The layout
    # (Columns or Row) asks for the cells; the painter (the Selector on an
    # ANSI line, a BBS::Petscii::CanvasMenu on a canvas) draws them.
    module Cells
      # Item +index+ as a cell +width+ wide, a list of segments (see
      # #paint): blank past the last item, a heading in its colour, the lit
      # one as a bar of plain text, the others as a key and a label.
      def cell(index, width)
        item = @items[index]
        return [[' ' * width, :text]] unless item
        return [[label(" #{item.label}", width), :heading]] if item.heading

        item_cell(item, index, width)
      end

      # The items on one row as segments, each a key letter and its label,
      # the lit one a bar; the items that do not fit are left off.
      def across_cells
        fitting = fitting_items
        pad = @width - fitting.sum { |item, _| word(item).length + 2 }
        fitting.flat_map { |item, i| across_cell(item, i) } << [' ' * pad, :text]
      end

      private

      # A selectable item as a cell: the lit one a bar of plain text, the
      # others a key and a label.
      def item_cell(item, index, width)
        prefix = key_width.positive? ? " #{key_text(index)} " : ' '
        return [[fit(prefix + plain(item.label), width), item.color || :bar, true]] if index == @index

        [[prefix, item.color || :key], [label(item.label.to_s, [width - prefix.length, 0].max), :text]]
      end

      # The items, with their indexes, that fit on one row.
      def fitting_items
        used = 0
        @items.each_with_index.take_while { |item, _| (used += word(item).length + 2) <= @width }
      end

      # The segments of menu line +number+ (1-based: the items' rows, then
      # the about row, then the status row).
      def line_segments(number)
        return @layout.segments(number, self) if number <= item_rows
        return about_segments if about? && number == item_rows + 1

        status_segments
      end

      def about_segments = [[fit(" #{plain(@items[@index].about)}", @width), :about]]

      def status_segments
        right = if !@typed.empty? then "##{@typed}"
                elsif pages > 1 then "#{page + 1}/#{pages}"
                else ''
                end
        left = " #{plain(@hint)}"[0, [@width - right.length - 1, 0].max]
        [["#{left}#{' ' * (@width - left.length - right.length)}#{right}", :hint]]
      end

      def word(item) = item.key ? "#{item.key.to_s.upcase} #{plain(item.label)}" : plain(item.label)

      def across_cell(item, index)
        return [[" #{word(item)} ", item.color || :bar, true]] if index == @index
        return [[" #{word(item)} ", :text]] unless item.key

        [[' ', :text], [item.key.to_s.upcase, item.color || :key], [" #{plain(item.label)} ", :text]]
      end

      def key_width
        @key_width ||= @numbers ? @items.size.to_s.length : @items.map { |i| i.key.to_s.length }.max
      end

      def key_text(index)
        key = @numbers ? (index + 1).to_s : @items[index].key.to_s.upcase
        key.rjust(key_width)
      end

      def fit(text, width) = text.length > width ? text[0, width] : text.ljust(width)

      # +text+ without its colours.
      def plain(text) = FrameBuffer.plain(text)

      # A label cut or padded to +width+ columns, its colours kept.
      def label(text, width)
        text = FrameBuffer.clip_ansi(text, width)
        "#{text}#{' ' * (width - FrameBuffer.visible_width(text))}"
      end
    end

    # How a Selector draws on an ANSI line, at the cursor: the whole menu
    # once, then the rows that change.
    module Drawing
      private

      def draw
        lines = (1..rows).map { |l| "#{' ' * @indent}#{paint(line_segments(l))}" }
        @session.write(lines.join(Ansi::CRLF))
        @cursor = Cursor.new(@session, row: lines.size, col: @indent + @width + 1)
        @session.write(park)
      end

      # +segments+ (<tt>[text, colour, reversed]</tt>, the colour a role of
      # COLORS or an item's own) as ANSI text.
      def paint(segments)
        segments.map do |text, color, reversed|
          sgr = color.is_a?(Symbol) ? @colors[color] : color
          reversed ? "#{sgr}#{Ansi::REVERSE}#{text}#{Ansi::REVERSE_OFF}#{@colors[:text]}" : "#{sgr}#{text}"
        end.join << @colors[:text]
      end

      def repaint(lines)
        out = lines.map { |l| row_at(l, paint(line_segments(l))) }.join
        @session.write(out << park)
      end

      # The cursor to the start of the lit item.
      def park = @cursor.move(@layout.line_of(@index), @indent + @layout.column_of(@index, @width))

      # The bytes that write +text+ (exactly #width columns) on row +row+.
      def row_at(row, text)
        out = @cursor.move(row, @indent + 1) << text
        @cursor.wrote(@width)
        out
      end

      def finish(result)
        @session.write(@cursor.move(rows, 1) << Ansi::CRLF)
        result
      end
    end

    include Cells
    include Drawing
  end
end
