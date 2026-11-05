# frozen_string_literal: true

module Rubbs
  module Modern
    class FrameBuffer
      # The word-wrap of FrameBuffer.wrap_ansi: it reads the text a token at a
      # time (an escape sequence, a word or a run of blanks) and breaks the
      # line before the word that would not fit, starting the next line with
      # the style that was active.
      class Wrap
        # One token: a CSI sequence (first group), a word (second) or a run
        # of whitespace (third).
        TOKEN = /(#{Ansi::CSI_RE})|([^\s\e]+)|(\s+)/

        # Wraps to lines of +width+ visible characters.
        def initialize(width)
          @width = width
        end

        # The lines of +text+, an Array of Strings with trailing spaces
        # removed; <tt>['']</tt> for no text.
        def lines(text)
          @lines   = []
          @line    = +''
          @visible = 0
          @sgr     = nil
          text.scan(TOKEN) { |seq, word, blank| seq ? escape(seq) : add(word || blank, blank) }
          @lines << @line.rstrip unless @line.empty?
          @lines.empty? ? [''] : @lines
        end

        private

        def escape(seq)
          @sgr = RESETS.include?(seq) ? nil : seq
          @line << seq
        end

        # Adds a word, or a run of blanks (+blank+), breaking the line first
        # when it would not fit: blanks that do not fit are dropped.
        def add(token, blank)
          fits = @visible.zero? || @visible + token.length <= @width
          if blank && !fits then return break_line
          elsif !fits then break_line
          end

          @line << token
          @visible += token.length
        end

        def break_line
          @lines << @line.rstrip
          @line    = @sgr ? @sgr.dup : +''
          @visible = 0
        end
      end

      private_constant :Wrap
    end
  end
end
