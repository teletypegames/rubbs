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
  #
  # A window that is not maximized can be moved and, when resizable?,
  # resized (`movable: false` turns it off): drag the title bar to move it,
  # the bottom right corner to size it. From the keyboard Ctrl-F5 (or F6)
  # starts it, Turbo Vision style: the arrows move the window, Shift and the
  # arrows size it (Tab switches the arrows between moving and sizing), and
  # Enter or Esc ends it. A window moved or sized keeps its place when the
  # terminal is resized, pulled back onto the screen if needed.
  class Window < Container
    ZOOM_KEYS    = %i[f5 alt_enter].freeze
    MOVE_KEYS    = %i[ctrl_f5 f6].freeze
    ARROWS       = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze
    DOUBLE_CLICK = 0.5
    MIN_WIDTH    = 24
    MIN_HEIGHT   = 7
    KBD_TITLES   = { move: ' Move: arrows · Shift+arrows or Tab: size · Enter: done ',
                     size: ' Size: arrows · Tab: move · Enter: done ' }.freeze

    attr_accessor :title, :modal, :shadow, :on_close, :close_key, :maximizable, :movable
    attr_writer :app

    def initialize(title: nil, modal: false, shadow: true, on_close: nil,
                   close_key: :escape, maximizable: false, movable: true, **kw)
      super(**kw)
      @title       = title
      @modal       = modal
      @shadow      = shadow
      @on_close    = on_close
      @close_key   = close_key
      @maximizable = maximizable
      @movable     = movable
      @maximized   = false
      @placed      = nil
      @drag        = nil
      @kbd_mode    = nil
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
      @kbd_mode  = nil
      @drag      = nil
      relayout(@app)
      :handled
    end

    def movable? = @movable && !@maximized && !@app.nil?
    def sizable? = movable? && resizable?

    # Moves (and, when resizable?, sizes) the window to the rect, kept on
    # the desktop; the window keeps it through later relayouts.
    def move_to(x, y, width = bounds.width, height = bounds.height)
      return unless movable?

      dx, dy, dw, dh = @app.desktop_rect
      width  = resizable? ? width.clamp([MIN_WIDTH, dw].min, dw) : bounds.width
      height = resizable? ? height.clamp([MIN_HEIGHT, dh].min, dh) : bounds.height
      x = x.clamp(dx, [dx + dw - width, dx].max)
      y = y.clamp(dy, [dy + dh - height, dy].max)
      @placed = [x, y, width, height]
      if resizable?
        place(x, y, width, height)
      else
        shift(x - bounds.x, y - bounds.y)
      end
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
      title = KBD_TITLES[@kbd_mode] if @kbd_mode
      frame.box(
        x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
        sgr: @kbd_mode || @drag ? style(:window_title_focused) : style(:window_border),
        fill_sgr: style(:window_bg), style: :double, title: title,
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
      if sizable? && bounds.width >= 6
        frame.move(bounds.x + bounds.width - 1, bounds.y + bounds.height - 1)
        frame.write('┘', sgr: style(:window_title))
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
      return keyboard_move(event) if @kbd_mode
      return drag(event) if @drag && event.mouse?
      return toggle_maximize if event.key? && zoomable? && ZOOM_KEYS.include?(event.key)
      if event.key? && MOVE_KEYS.include?(event.key) && movable?
        @kbd_mode = :move
        return :handled
      end

      if event.mouse? && event.mouse.kind == :press && event.mouse.button == :left
        if @on_close != false && event.y == bounds.y && event.x >= bounds.x + 2 && event.x <= bounds.x + 4
          return close
        end
        return toggle_maximize if zoomable? && title_click?(event)
        return start_drag(:size, event) if sizable? && corner?(event)
        return start_drag(:move, event) if movable? && event.y == bounds.y
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
      # A modified key nothing takes (Shift-Down in a list) acts as the key.
      if result.nil? && event.key? && (plain = event.key.to_s[/\A(?:shift|ctrl|alt|ctrl_shift)_((?:page_)?(?:up|down)|left|right|home|end)\z/, 1])
        result = focus_manager.dispatch(Event.key(plain.to_sym))
      end
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

    def corner?(event)
      event.y == bounds.y + bounds.height - 1 && event.x >= bounds.x + bounds.width - 2 &&
        event.x <= bounds.x + bounds.width - 1
    end

    def start_drag(mode, event)
      @drag = { mode: mode, x: event.x, y: event.y, rect: [bounds.x, bounds.y, bounds.width, bounds.height] }
      :handled
    end

    # Follows the mouse while the button is held; the release ends it.
    def drag(event)
      x, y, w, h = @drag[:rect]
      dx = event.x - @drag[:x]
      dy = event.y - @drag[:y]
      if dx.zero? && dy.zero?
        nil
      elsif @drag[:mode] == :move
        move_to(x + dx, y + dy, w, h)
      else
        move_to(x, y, w + dx, h + dy)
      end
      @drag = nil if event.mouse.kind == :release
      :handled
    end

    def keyboard_move(event)
      return :handled unless event.key?

      key = event.key
      if %i[enter escape].include?(key) || MOVE_KEYS.include?(key)
        @kbd_mode = nil
      elsif key == :tab && sizable?
        @kbd_mode = @kbd_mode == :move ? :size : :move
      elsif (step = ARROWS[key.to_s.delete_prefix('shift_').to_sym])
        size = (@kbd_mode == :size || key.to_s.start_with?('shift_')) && sizable?
        x, y, w, h = bounds.x, bounds.y, bounds.width, bounds.height
        size ? move_to(x, y, w + step[0], h + step[1]) : move_to(x + step[0], y + step[1], w, h)
      end
      :handled
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
      return move_to(*@placed) if @placed && !@maximized
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
