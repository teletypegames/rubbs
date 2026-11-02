# frozen_string_literal: true

module BBS
  module Widgets
    # A scrollable text buffer: an Array of lines, which may carry ANSI
    # colour codes, with a scrollbar when they do not fit.
    class ScrollView < Widget
      include Drawing

      # [lines]  the Array of lines shown; they may carry ANSI colour codes
      # [scroll] index of the line on the top row
      attr_accessor :lines, :scroll

      # Creates a view of +lines+ scrolled to the top.
      def initialize(lines: [], **kw)
        super(**kw)
        @lines  = lines
        @scroll = 0
      end

      # True: a scroll view takes the focus.
      def focusable? = true

      # Draws the visible lines into the bounds of +frame+, each cut to the
      # width, and a scrollbar in the rightmost column when the lines do not
      # fit.
      def render(frame)
        return if no_room?

        bounds.height.times { |r| draw_row(frame, r) }
        draw_scrollbar(frame) if @lines.size > bounds.height && bounds.width > 1
      end

      # Scrolls with Up, Down, Page Up, Page Down, Home and End, and by three
      # lines on the mouse wheel. Returns :handled, or +nil+ for other events.
      def handle_event(event)
        if event.mouse?
          return nil unless event.mouse.kind == :wheel

          return scroll_to(@scroll + (event.mouse.button == :up ? -WHEEL_STEP : WHEEL_STEP))
        end
        target = event.key? && target_of(event.key)
        target ? scroll_to(target) : nil
      end

      private

      def max_scroll = [@lines.size - bounds.height, 0].max

      # The top line key +name+ scrolls to, or +nil+.
      def target_of(name)
        case name
        when :up        then @scroll - 1
        when :down      then @scroll + 1
        when :page_up   then @scroll - bounds.height
        when :page_down then @scroll + bounds.height
        when :home      then 0
        when :end       then max_scroll
        end
      end

      def scroll_to(top)
        @scroll = top.clamp(0, max_scroll)
        :handled
      end

      def draw_row(frame, row)
        blank(frame, row, style(:text))
        line = @lines[@scroll + row] or return

        put_ansi(frame, 0, row, FrameBuffer.clip_ansi(line.to_s, bounds.width), style(:text))
      end

      def draw_scrollbar(frame)
        col = bounds.width - 1
        bounds.height.times { |r| put(frame, col, r, '│', style(:scrollbar)) }
        put(frame, col, thumb_row, '█', style(:scrollbar_thumb))
      end

      # The row of the scrollbar's thumb.
      def thumb_row
        (@scroll * (bounds.height - 1).to_f / [@lines.size - bounds.height, 1].max).to_i
      end
    end
  end
end
