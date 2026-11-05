# frozen_string_literal: true

module BBS
  module Kit
    module Modern
      # A screen of the modern face: its #lines from the top, after the
      # margin, at most a screenful (the last row stays free).
      class Screen < BBS::Page
        include Style

        # Prints #lines on +frame+.
        def draw(frame) = print_lines(frame, lines, x: look.margin + 1, limit: rows - 1)

        # The lines of the screen; none by default.
        def lines = []
      end

      # A screen of given lines: a question, a notice, until a key
      # (BBS::Pages#show).
      class Lines < Screen
        # The lines.
        attr_reader :lines

        # A screen of +lines+.
        def initialize(lines)
          super()
          @lines = lines
        end
      end

      # The line a runner of modern screens reads at the bottom of the
      # screen (BBS::Pages#read_line): its hint above it, the label, the
      # words, the cursor after them.
      module Prompt
        include Style

        private

        # Draws the line being read on +frame+.
        def prompt(frame)
          label, shown = prompt_parts
          print_lines(frame, [hint_line, prompt_line(label, shown)], x: look.margin + 1, y: rows - 2, clear: true)
          cursor(rows - 1, look.margin + label.length + shown.length + 2)
        end

        # The label and as much of the words as fits after it.
        def prompt_parts
          label = line.label.to_s
          [label, line.tail(width - label.length - 3)]
        end

        def prompt_line(label, shown) = "#{look.accent}#{BOLD}#{label}#{RESET} #{TEXT}#{shown}#{RESET}"

        def hint_line = "#{DIM}#{fit(line.hint.to_s, width)}#{RESET}"
      end
    end
  end
end
