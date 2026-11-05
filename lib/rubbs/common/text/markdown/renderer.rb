# frozen_string_literal: true

module Rubbs
  module Common
    module Text
      module Markdown
        # Turns the source lines of a Markdown text into terminal lines, a
        # block at a time: each block kind is a method that looks at the line,
        # and when the line starts its block, writes the block and returns how
        # many source lines it took. A line no block takes joins the paragraph.
        class Renderer
          # The block kinds in the order they are tried.
          BLOCKS = %i[fence code blank heading table rule quote bullet numbered].freeze
          # The style of each heading level; deeper levels take +:h3+.
          HEADINGS = { 1 => :h1, 2 => :h2 }.freeze

          # A renderer for lines +width+ columns wide in +styles+ (see
          # Markdown::STYLE_ROLES).
          def initialize(width, styles)
            @width  = width
            @styles = styles
          end

          # The terminal lines of the source +lines+, an Array of String.
          def render(lines)
            @lines     = lines
            @out       = []
            @paragraph = []
            @code      = false
            index = 0
            index += step(index) while index < lines.size
            flush
            @out
          end

          private

          def base = @styles[:base]

          # Renders the block that starts at line +index+. Returns the lines it
          # took.
          def step(index)
            line = @lines[index]
            BLOCKS.each do |kind|
              taken = send(kind, line, index)
              return taken if taken
            end
            @paragraph << line.strip
            1
          end

          # Ends the paragraph, writes what the block yields to, and returns
          # +taken+, the source lines of the block.
          def take(taken = 1)
            flush
            yield if block_given?
            taken
          end

          def flush
            return if @paragraph.empty?

            @out.concat(wrapped(@paragraph.join(' ').gsub(Patterns::WHITESPACE, ' ').strip, @width))
            @paragraph.clear
          end

          def wrapped(text, width) = Modern::FrameBuffer.wrap_ansi(Inline.style(text, @styles), width)

          # The width left after +prefix+ columns, at least one.
          def inner(prefix) = [@width - prefix, 1].max

          def fence(line, _index)
            return unless line.lstrip.start_with?('```')

            take { @code = !@code }
          end

          def code(line, _index)
            return unless @code

            take { @out << "#{@styles[:code]}#{Modern::FrameBuffer.clip_ansi(line, @width)}#{base}" }
          end

          def blank(line, _index)
            take { @out << '' } if line.strip.empty?
          end

          def heading(line, _index)
            m = line.match(HEADING) or return
            style = @styles[HEADINGS.fetch(m[1].length, :h3)]
            take { wrapped(m[2].strip, @width).each { |l| @out << "#{style}#{l}#{base}" } }
          end

          def table(line, index)
            delimiter = @lines[index + 1]
            return unless line.include?('|') && delimiter && Table.delimiter?(delimiter)

            rows = @lines.drop(index + 2).take_while { |l| table_row?(l) }
            take(rows.size + 2) { @out.concat(Table.new(line, delimiter, rows, @styles).lines(@width)) }
          end

          def table_row?(line) = line.include?('|') && !line.strip.empty? && !line.lstrip.start_with?('```')

          def rule(line, _index)
            take { @out << "#{@styles[:rule]}#{'─' * @width}#{base}" } if line.match?(RULE)
          end

          def quote(line, _index)
            m = line.match(QUOTE) or return
            take { wrapped(m[1], inner(2)).each { |l| @out << "#{@styles[:quote]}│ #{base}#{l}" } }
          end

          def bullet(line, index)
            m = line.match(BULLET_ITEM) or return
            item(index, m[2], m[1].length, '•')
          end

          def numbered(line, index)
            m = line.match(NUMBERED_ITEM) or return
            item(index, m[3], m[1].length, "#{m[2]}.")
          end

          # A list item from line +index+: its +mark+ after +indent+ spaces on
          # the first line, its text wrapped under the text.
          def item(index, first, indent, mark)
            body, taken = item_body(first, index)
            under = indent + mark.length + 1
            take(taken) do
              wrapped(body, inner(under)).each_with_index do |l, k|
                @out << (k.zero? ? "#{' ' * indent}#{@styles[:bullet]}#{mark}#{base} #{l}" : "#{' ' * under}#{l}")
              end
            end
          end

          # A list item's text with its indented continuation lines, and how
          # many source lines it took.
          def item_body(first, index)
            more = @lines.drop(index + 1).take_while { |l| l.match?(CONTINUATION) && !l.match?(ITEM_START) }
            [[first.strip, *more.map(&:strip)].join(' '), more.size + 1]
          end
        end

        private_constant :Renderer
      end
    end
  end
end
