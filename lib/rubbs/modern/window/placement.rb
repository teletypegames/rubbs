# frozen_string_literal: true

require_relative '../widgets/container'

module Rubbs
  module Modern
    class Window < Widgets::Container
      # Where a Window stands and how big it is: zooming, moving and sizing
      # with the mouse and the keyboard, and keeping its place when the
      # terminal is resized.
      module Placement
        # Maximizes the window to the desktop, or puts it back to its normal
        # place, ending any move or size in progress. Does nothing unless
        # #zoomable?. Returns +:handled+.
        def toggle_maximize
          return :handled unless zoomable?

          @maximized = !@maximized
          @kbd_mode  = nil
          @drag      = nil
          relayout(@app)
          :handled
        end

        # Moves (and, when resizable?, sizes) the window to the rect, kept on
        # the desktop; the window keeps it through later relayouts. A resizable
        # window is clamped to MIN_WIDTH by MIN_HEIGHT and the desktop size; any
        # other keeps its size. Does nothing unless #movable?.
        def move_to(x, y, width = bounds.width, height = bounds.height)
          return unless movable?

          @placed = on_desktop(x, y, *fitted_size(width, height))
          resizable? ? place(*@placed) : shift(@placed[0] - bounds.x, @placed[1] - bounds.y)
        end

        # Called by the Application when the terminal is resized. The default
        # keeps the window's size and re-centers it, shifting every descendant
        # along. Subclasses whose geometry depends on the terminal size override
        # this (such as Rubbs::Modern::Windows::MasterDetail). A window moved or sized by
        # the user goes back to its place, a resizable one is placed at the
        # desktop (maximized) or its +normal_rect+.
        def relayout(app)
          return move_to(*@placed) if @placed && !@maximized
          return place(*(@maximized ? app.desktop_rect : normal_rect)) if resizable?

          centre_in(app)
        end

        # Moves the window and all its descendants by +dx+ columns and +dy+
        # rows.
        def shift(dx, dy)
          return if dx.zero? && dy.zero?

          walk do |w|
            b = w.bounds
            w.bounds = Widgets::Widget::Rect.new(b.x + dx, b.y + dy, b.width, b.height)
          end
        end

        private

        # Shifts the window to the middle of +app+'s screen.
        def centre_in(app)
          shift(centred(app.cols, bounds.width) - bounds.x, centred(app.rows, bounds.height) - bounds.y)
        end

        # The start of +size+ cells in the middle of +screen+ cells, from 1.
        def centred(screen, size) = [((screen - size) / 2) + 1, 1].max

        # +width+ and +height+ clamped to the desktop for a resizable window;
        # the window's own size otherwise.
        def fitted_size(width, height)
          return [bounds.width, bounds.height] unless resizable?

          _, _, dw, dh = @app.desktop_rect
          [width.clamp([MIN_WIDTH, dw].min, dw), height.clamp([MIN_HEIGHT, dh].min, dh)]
        end

        # The rect at +x+, +y+ of +width+ by +height+ pulled onto the desktop.
        def on_desktop(x, y, width, height)
          dx, dy, dw, dh = @app.desktop_rect
          [x.clamp(dx, [dx + dw - width, dx].max), y.clamp(dy, [dy + dh - height, dy].max), width, height]
        end

        # A click that zooms a #zoomable? window: on the zoom gadget, or a
        # second click on the title bar soon after a first.
        def zoom_click?(event)
          return false unless zoomable? && on_title_bar?(event)

          event.x.between?(zoom_x, zoom_x + GADGET_WIDTH - 1) || double_click?
        end

        def on_title_bar?(event) = event.y == bounds.y && event.x.between?(bounds.x, bounds.x + bounds.width - 1)

        def double_click?
          now    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          double = @title_clicked_at && now - @title_clicked_at < DOUBLE_CLICK
          @title_clicked_at = double ? nil : now
          double
        end

        # Whether the mouse +event+ is on the bottom right size corner.
        def corner?(event)
          right = bounds.x + bounds.width - 1
          event.y == bounds.y + bounds.height - 1 && event.x.between?(right - CORNER_HIT + 1, right)
        end

        # Starts a mouse drag in +mode+ (+:move+ or +:size+) from the position
        # of +event+, remembering the current bounds. Returns +:handled+.
        def start_drag(mode, event)
          @drag = { mode: mode, x: event.x, y: event.y, rect: [bounds.x, bounds.y, bounds.width, bounds.height] }
          :handled
        end

        # Follows the mouse while the button is held, moving or sizing the
        # window through #move_to; the release ends it. Returns +:handled+.
        def drag(event)
          dx = event.x - @drag[:x]
          dy = event.y - @drag[:y]
          resize_by(@drag[:rect], @drag[:mode], dx, dy) unless dx.zero? && dy.zero?
          @drag = nil if event.mouse.kind == :release
          :handled
        end

        # Moves (+:move+) or sizes (+:size+) the window from +rect+ by +dx+,
        # +dy+.
        def resize_by(rect, mode, dx, dy)
          x, y, w, h = rect
          mode == :move ? move_to(x + dx, y + dy, w, h) : move_to(x, y, w + dx, h + dy)
        end

        # Handles +event+ in keyboard move/size mode: the arrows move or (with
        # Shift, or in size mode) size the window by one cell, Tab switches
        # between moving and sizing when #sizable?, and Enter, Esc or a
        # MOVE_KEYS key ends the mode. Every key is swallowed: returns
        # +:handled+.
        def keyboard_move(event)
          key_move(event.key) if event.key?
          :handled
        end

        # The keys that end moving or sizing from the keyboard.
        def end_key?(key) = %i[enter escape].include?(key) || MOVE_KEYS.include?(key)

        def key_move(key)
          return @kbd_mode = nil if end_key?(key)
          return @kbd_mode = @kbd_mode == :move ? :size : :move if key == :tab && sizable?

          step = ARROWS[key.to_s.delete_prefix('shift_').to_sym]
          resize_by([bounds.x, bounds.y, bounds.width, bounds.height], step_mode(key), *step) if step
        end

        # Whether an arrow +key+ sizes (+:size+) or moves (+:move+) the window.
        def step_mode(key)
          size = (@kbd_mode == :size || key.to_s.start_with?('shift_')) && sizable?
          size ? :size : :move
        end
      end
    end
  end
end
