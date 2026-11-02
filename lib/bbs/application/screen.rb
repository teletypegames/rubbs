# frozen_string_literal: true

module BBS
  class Application
    # How an Application draws: the bars and the root laid out, everything
    # drawn into a fresh BBS::FrameBuffer, and only the difference to the
    # screen the caller has sent.
    module Screen
      # The screen between the menubar and the statusbar, as [x, y, w, h]:
      # where a maximized window goes.
      def desktop_rect
        top = bar_rows(@menubar)
        [1, 1 + top, cols, [rows - top - bar_rows(@statusbar), MIN_DESKTOP_ROWS].max]
      end

      private

      # Draws the application and sends what changed: the whole screen
      # after a clear on the first frame and after a resize.
      def render_screen
        fresh = new_frames
        draw_frame
        delta = @next.diff(@committed)
        return unless fresh || !delta.empty?

        @session.write("#{Ansi::HIDE_CURSOR}#{Ansi::CLEAR if fresh}#{delta}#{Ansi::SHOW_CURSOR}")
        @committed = @next
      end

      # Starts the next frame, laying everything out again; on a resize the
      # windows too. Returns whether the screen starts over (the first frame
      # or a new size).
      def new_frames
        resized = @committed && (@committed.cols != cols || @committed.rows != rows)
        fresh   = @committed.nil? || resized
        @committed = FrameBuffer.new(cols, rows) if fresh
        @next      = FrameBuffer.new(cols, rows)
        relayout!
        @windows.each { |w| w.relayout(self) } if resized
        fresh
      end

      def draw_frame
        @next.fill(x: 1, y: 1, width: cols, height: rows, sgr: @theme[:screen])
        [@root, *@windows, @menubar].compact.each { |part| part.render(@next) }
        return unless @statusbar

        @statusbar.message = @menubar&.selected_hint
        @statusbar.render(@next)
      end

      def relayout!
        top = bar_rows(@menubar)
        @menubar&.layout(1, 1, cols, BAR_HEIGHT)
        @statusbar&.layout(1, rows, cols, BAR_HEIGHT)
        @root.layout(1, 1 + top, cols, rows - top - bar_rows(@statusbar))
      end

      # The rows +bar+ takes: BAR_HEIGHT, or none without a bar.
      def bar_rows(bar) = bar ? BAR_HEIGHT : 0
    end
  end
end
