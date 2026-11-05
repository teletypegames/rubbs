# frozen_string_literal: true

module Rubbs
  module Common
    module Text
      module Markdown
        # A GFM table: a header row, a delimiter row that sets the alignments,
        # and the body rows, drawn as box-drawn ANSI lines.
        class Table
          # Whether +line+ is a table delimiter row, e.g. <tt>|---|:--:|---:|</tt>.
          def self.delimiter?(line)
            return false unless line.include?('-')

            cells = cells(line)
            !cells.empty? && cells.all? { |c| c.match?(DELIMITER_CELL) }
          end

          # The trimmed cells of a <tt>| a | b |</tt> row; the leading and the
          # trailing pipe may be missing.
          def self.cells(line)
            s = line.strip
            s = s[1..] if s.start_with?('|')
            s = s[0..-2] if s.end_with?('|')
            s.split('|').map(&:strip)
          end

          # The table of the +header+ line, the +delimiter+ line and the body
          # +rows+ (lines), its cells styled inline with +styles+.
          def initialize(header, delimiter, rows, styles)
            @styles = styles
            @ncols  = Table.cells(header).size
            @aligns = aligns(delimiter)
            @rows   = [header, *rows].map do |line|
              cells = Table.cells(line)
              Array.new(@ncols) { |c| Inline.style(cells[c].to_s, styles) }
            end
          end

          # The lines of the table, fitting +width+: the widest columns shrink
          # when it overflows. Empty for a table without columns.
          def lines(width)
            return [] if @ncols.zero?

            @widths = shrink(natural_widths, [width - (@ncols * 3) - 1, @ncols].max)
            [border('┌', '┬', '┐'), row(@rows.first, header: true), border('├', '┼', '┤'),
             *@rows.drop(1).map { |r| row(r) }, border('└', '┴', '┘')]
          end

          private

          # The alignment of each column (+:left+, +:center+ or +:right+) from
          # the colons of the delimiter row, padded or cut to the columns.
          def aligns(delimiter)
            found = Table.cells(delimiter).map do |c|
              next :center if c.start_with?(':') && c.end_with?(':')

              c.end_with?(':') ? :right : :left
            end
            Array.new(@ncols) { |c| found[c] || :left }
          end

          def natural_widths = (0...@ncols).map { |c| @rows.map { |r| Modern::FrameBuffer.visible_width(r[c]) }.push(1).max }

          # +widths+ with the widest one narrowed a column at a time until they
          # fit +room+.
          def shrink(widths, room)
            while widths.sum > room
              widest = widths.each_index.max_by { |c| widths[c] }
              break if widths[widest] <= 1

              widths[widest] -= 1
            end
            widths
          end

          def border(left, mid, right)
            "#{@styles[:rule]}#{left}#{@widths.map { |w| '─' * (w + 2) }.join(mid)}#{right}#{@styles[:base]}"
          end

          def row(cells, header: false)
            bar = "#{@styles[:rule]}│#{@styles[:base]}"
            bar + cells.each_with_index.map { |cell, c| " #{fit(cell, c, header)} " }.join(bar) + bar
          end

          # Cell +cell+ of column +c+ clipped or padded to the column's width
          # and alignment; a header cell in the bold style.
          def fit(cell, c, header)
            base    = @styles[:base]
            content = header ? "#{@styles[:bold]}#{cell}#{base}" : cell
            pad     = @widths[c] - Modern::FrameBuffer.visible_width(cell)
            return "#{Modern::FrameBuffer.clip_ansi(content, @widths[c])}#{base}" if pad.negative?

            case @aligns[c]
            when :right  then "#{' ' * pad}#{content}"
            when :center then "#{' ' * (pad / 2)}#{content}#{' ' * (pad - (pad / 2))}"
            else "#{content}#{' ' * pad}"
            end
          end
        end

        private_constant :Table
      end
    end
  end
end
