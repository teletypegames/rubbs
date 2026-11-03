# frozen_string_literal: true

module BBS
  module Petscii
    class Face
      # The masthead of a Face: lines written one under the other.
      class Masthead
        include Colors

        # Evaluates the declarations of the block.
        def initialize(&)
          @parts = []
          instance_eval(&)
        end

        # Lines as they are (a drawing in PETSCII colours).
        def art(lines) = @parts << [:lines, Array(lines)]

        # +word+ in reversed blocks (BBS::BlockFont.petscii), one colour per
        # row.
        def logo(word, colors:, glyphs: {}, indent: 2)
          @parts << [:lines, BlockFont.petscii(word, colors: colors, glyphs: glyphs, indent: indent)]
        end

        # A line of text in +color+, +indent+ spaces in (default 1); a block
        # gives the text (evaluated in the face).
        def line(text = nil, color: LG, indent: 1, &block) = @parts << [:line, block || text, color, indent]

        # A dim rule across the screen.
        def rule = @parts << [:rule]

        # +count+ empty lines.
        def gap(count = 1) = @parts << [:lines, [''] * count]

        # Writes the masthead on +face+.
        def draw(face)
          @parts.each do |kind, content, color, indent|
            case kind
            when :lines then content.each { |l| face.puts(l) }
            when :rule  then face.puts(face.rule_line)
            else
              text = content.is_a?(Proc) ? face.instance_exec(&content) : content
              face.puts("#{' ' * indent}#{color}#{text}#{LG}")
            end
          end
        end
      end
    end
  end
end
