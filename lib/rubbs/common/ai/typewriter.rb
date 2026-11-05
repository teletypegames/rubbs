# frozen_string_literal: true

module Rubbs
  module Common
    module AI
      # Types streamed text onto a FakeOS console, word-wrapped to the caller's
      # terminal under a prefix:
      #
      #   ACP: The bus is quiet tonight, and I am
      #        listening to it.
      #
      # Words are held back until they are whole, and whitespace is written only
      # before the next word, so a reply never ends on a dangling blank line.
      class Typewriter
        # Creates a typewriter on +io+ (a FakeOS console) and prints +prefix+.
        #
        # [prefix] printed once; wrapped lines are indented by its length
        # [style]  the FakeOS style the text is printed in
        # [width]  the line width, by default one less than the terminal's;
        #          at least 20 columns are left for the text
        def initialize(io, prefix: '', style: :text, width: nil)
          @io      = io
          @style   = style
          @indent  = ' ' * prefix.size
          @width   = [(width || (io.cols - 1)) - prefix.size, 20].max
          @col     = 0
          @gap     = nil
          @pending = +''
          @io.print prefix, style: @style, newline: 0
        end

        # Adds +piece+ of the streamed text, printing every word it completes
        # and keeping the unfinished one back.
        def write(piece)
          @pending << piece
          while (m = @pending.match(Text::WHITESPACE))
            word(m.pre_match)
            @gap = "#{@gap}#{m[0]}"
            @pending = m.post_match
          end
        end

        # Writes the last word and +newlines+ line breaks.
        def finish(newlines: 2)
          word(@pending)
          @pending = +''
          @io.newline(newlines)
        end

        private

        def word(text)
          return if text.empty?

          space_before(text) if @col.positive?
          out(text)
          @col += text.size
          @gap = nil
        end

        # A line break before +text+ when the gap had one or the line is full,
        # else one space when there was a gap.
        def space_before(text)
          if @gap&.include?("\n") || @col + 1 + text.size > @width
            out("#{Modern::Ansi::CRLF}#{@indent}")
            @col = 0
          elsif @gap
            out(' ')
            @col += 1
          end
        end

        def out(text) = @io.print(text, style: @style, newline: 0)
      end
    end
  end
end
