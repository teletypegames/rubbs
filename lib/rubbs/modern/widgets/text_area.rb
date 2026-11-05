# frozen_string_literal: true

module Rubbs
  module Modern
    module Widgets
      # A multi-line text editor. Lines are not wrapped: a line wider than the
      # area is cut off.
      class TextArea < Widget
        include Drawing

        # The editing keys and the method each one calls.
        KEYS = {
          left:      :left,
          right:     :right,
          up:        :up,
          down:      :down,
          home:      :to_start,
          end:       :to_end,
          enter:     :split_line,
          backspace: :backspace
        }.freeze

        # Callable invoked as <tt>call(value, area)</tt> after each edit.
        attr_accessor :on_change

        # Creates an editor holding +value+ (lines separated by LF), accepting
        # at most +max_length+ characters (default 8000).
        def initialize(value: '', max_length: 8_000, on_change: nil, **kw)
          super(**kw)
          @lines      = value.empty? ? [+''] : value.split("\n", -1).map(&:dup)
          @max_length = max_length
          @on_change  = on_change
          @row        = 0
          @col        = 0
          @scroll     = 0
        end

        # True: a text area takes the focus.
        def focusable? = true

        # The whole text, lines joined with LF.
        def value = @lines.join("\n")
        # The length of #value in characters.
        def length = value.length

        # Draws the visible lines into the bounds of +frame+, with an
        # underscore cursor when focused.
        def render(frame)
          return if no_room?

          bounds.height.times { |r| draw_row(frame, r) }
          draw_cursor(frame) if focused
        end

        # Edits the text on a key event: arrows move the cursor (Left and
        # Right wrap across lines), Home and End go to the line's ends, Enter
        # splits the line, Backspace deletes or joins with the line above, and
        # a printable character is inserted while #length is under
        # +max_length+. Returns :handled, or +nil+ for other keys, mouse events,
        # or when disabled.
        def handle_event(event)
          return nil unless event.key? && enabled
          return send(KEYS[event.key]).then { :handled } if KEYS.key?(event.key)

          event.char? ? insert(event.key) : nil
        end

        private

        def sgr = focused ? style(:input_focused) : style(:input)

        def line = @lines[@row]

        def draw_row(frame, row)
          blank(frame, row, sgr)
          text = @lines[@scroll + row] or return

          put(frame, 0, row, text[0, bounds.width].to_s, sgr)
        end

        def draw_cursor(frame)
          row = @row - @scroll
          put(frame, [@col, bounds.width - 1].min, row, '_', sgr) if row.between?(0, bounds.height - 1)
        end

        def left
          return go(@row - 1, @lines[@row - 1].length) if @col.zero? && @row.positive?

          go(@row, @col - 1)
        end

        def right
          return go(@row + 1, 0) if @col == line.length && @row < @lines.size - 1

          go(@row, @col + 1)
        end

        def up = go(@row - 1, @col)

        def down = go(@row + 1, @col)

        def to_start = go(@row, 0)

        def to_end = go(@row, line.length)

        # Puts the cursor on +row+, +col+, both kept in the text, and scrolls
        # to it.
        def go(row, col)
          @row = row.clamp(0, @lines.size - 1)
          @col = col.clamp(0, line.length)
          ensure_visible
        end

        def split_line
          tail = +(line[@col..] || '')
          @lines[@row] = +(line[0, @col] || '')
          @lines.insert(@row + 1, tail)
          go(@row + 1, 0)
          changed
        end

        def backspace
          if @col.positive?
            line.slice!(@col - 1)
            @col -= 1
          elsif @row.positive?
            join_with_line_above
          end
          changed
        end

        def join_with_line_above
          length = @lines[@row - 1].length
          @lines[@row - 1] += @lines.delete_at(@row)
          go(@row - 1, length)
        end

        def insert(char)
          return :handled unless length < @max_length

          line.insert(@col, char)
          @col += 1
          changed
        end

        def changed
          @on_change&.call(value, self)
          :handled
        end

        def ensure_visible
          @scroll = @row if @row < @scroll
          @scroll = @row - bounds.height + 1 if @row >= @scroll + bounds.height
          @scroll = [@scroll, 0].max
        end
      end
    end
  end
end
