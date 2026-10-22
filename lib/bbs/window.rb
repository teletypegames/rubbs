# frozen_string_literal: true

require_relative 'container'
require_relative 'focus_manager'

module BBS
  # A Window is a top-level Container with its own border, title, and focus
  # manager. The Application stacks windows; the top window is the modal /
  # active one and receives input first.
  #
  # A `maximizable` window that can lay itself out at any size (`resizable?`:
  # MasterDetail, Stream, Form, a scrolling Info) gets a zoom gadget in its
  # top right corner, Turbo Vision style: [↑] fills the desktop between the
  # menubar and the statusbar, [↕] puts it back. F5, Alt-Enter and a double
  # click on the title bar do the same.
  class Window < Container
    ZOOM_KEYS    = %i[f5 alt_enter].freeze
    DOUBLE_CLICK = 0.5

    attr_accessor :title, :modal, :shadow, :on_close, :close_key, :maximizable
    attr_writer :app

    def initialize(title: nil, modal: false, shadow: true, on_close: nil,
                   close_key: :escape, maximizable: false, **kw)
      super(**kw)
      @title       = title
      @modal       = modal
      @shadow      = shadow
      @on_close    = on_close
      @close_key   = close_key
      @maximizable = maximizable
      @maximized   = false
      @focus_mgr   = nil
    end

    def maximized? = @maximized

    # True for windows that can lay out their content at any size; they
    # override `place(x, y, width, height)` and `normal_rect`.
    def resizable? = false

    def zoomable? = @maximizable && resizable? && !@app.nil?

    def toggle_maximize
      return :handled unless zoomable?

      @maximized = !@maximized
      relayout(@app)
      :handled
    end

    def focus_manager
      @focus_mgr ||= FocusManager.new(self)
    end

    def reset_focus
      @focus_mgr = FocusManager.new(self)
    end

    def render(frame)
      if @shadow && !@maximized
        frame.shadow(x: bounds.x, y: bounds.y, width: bounds.width,
                     height: bounds.height, sgr: style(:window_shadow))
      end
      show_close = @on_close != false && bounds.width >= 6
      show_zoom  = zoomable? && bounds.width >= 14
      title      = @title
      title      = title.to_s[0, [bounds.width - 14, 0].max] if show_zoom
      frame.box(
        x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
        sgr: style(:window_border), fill_sgr: style(:window_bg),
        style: :double, title: title,
        title_sgr: focused ? style(:window_title_focused) : style(:window_title),
        title_indent: show_close ? 4 : 0
      )
      # Close gadget — Turbo Vision style "[■]"
      if show_close
        frame.move(bounds.x + 2, bounds.y)
        frame.write('[■]', sgr: style(:window_title))
      end
      if show_zoom
        frame.move(zoom_x, bounds.y)
        frame.write(@maximized ? '[↕]' : '[↑]', sgr: style(:window_title))
      end
      @children.each { |c| c.render(frame) if c.visible }
    end

    def hit_test(x, y)
      # close gadget area
      if @on_close != false && y == bounds.y &&
         x >= bounds.x + 2 && x <= bounds.x + 4
        return self
      end
      super
    end

    def handle_event(event)
      return toggle_maximize if event.key? && zoomable? && ZOOM_KEYS.include?(event.key)

      if event.mouse? && event.mouse.kind == :press && event.mouse.button == :left
        if @on_close != false && event.y == bounds.y && event.x >= bounds.x + 2 && event.x <= bounds.x + 4
          return close
        end
        return toggle_maximize if zoomable? && title_click?(event)
        if event.mouse.button == :left
          hit = hit_test(event.x, event.y)
          focus_manager.focus(hit) if hit&.focusable?
        end
      end

      # Route wheel scrolling to whatever widget is under the cursor, so a
      # scrollable pane responds even when keyboard focus is elsewhere.
      if event.mouse? && event.mouse.kind == :wheel
        hit = hit_test(event.x, event.y)
        if hit && hit != self && hit != focus_manager.focused
          res = hit.handle_event(event)
          return res if res
        end
      end

      result = focus_manager.handle_focus_key(event) ? :handled : nil
      result ||= focus_manager.dispatch(event)
      return result if result

      # A key the focused widget left alone presses the button it is the
      # hotkey of: "y" or Alt-Y for "&Yes".
      if event.key? && (button = hotkey_button(event.key))
        return button.fire
      end

      if event.key? && event.key == @close_key
        return close
      end
      nil
    end

    # The Application closes the window and calls on_close (see
    # Application#close_window), so the callback runs once.
    def close = :close_window

    def zoom_x = bounds.x + bounds.width - 5

    # The zoom gadget, or a second click on the title bar soon after a first.
    def title_click?(event)
      return false unless event.y == bounds.y && event.x.between?(bounds.x, bounds.x + bounds.width - 1)
      return true if event.x.between?(zoom_x, zoom_x + 2)

      now    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      double = @title_clicked_at && now - @title_clicked_at < DOUBLE_CLICK
      @title_clicked_at = double ? nil : now
      double
    end

    def hotkey_button(key)
      letter = key.is_a?(String) && key.length == 1 ? key.downcase : key.to_s[/\Aalt_(.)\z/, 1]
      return nil unless letter

      focusable_descendants.find { |w| w.is_a?(Widgets::Button) && w.enabled && w.hotkey == letter }
    end

    # Called once per Application idle tick (~1s). Override in subclasses that
    # need to poll for asynchronous updates (e.g. BBS::Windows::Stream).
    def tick(app); end

    # Called by the Application when the terminal is resized. The default
    # keeps the window's size and re-centers it, shifting every descendant
    # along. Subclasses whose geometry depends on the terminal size override
    # this (e.g. BBS::Windows::MasterDetail).
    def relayout(app)
      return place(*(@maximized ? app.desktop_rect : normal_rect)) if resizable?

      dx = [(app.cols - bounds.width) / 2 + 1, 1].max - bounds.x
      dy = [(app.rows - bounds.height) / 2 + 1, 1].max - bounds.y
      shift(dx, dy)
    end

    # Move the window and all its descendants by (dx, dy).
    def shift(dx, dy)
      return if dx.zero? && dy.zero?
      walk do |w|
        b = w.bounds
        w.bounds = Widget::Rect.new(b.x + dx, b.y + dy, b.width, b.height)
      end
    end
  end
end
