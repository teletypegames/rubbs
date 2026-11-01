# frozen_string_literal: true

require_relative 'container'
require_relative 'focus_manager'

module BBS
  # A Window is a top-level Container with its own border, title, and focus
  # manager. The Application stacks windows; the top window is the active
  # one and receives input first. Windows that are not +modal+ can be
  # switched, Turbo Vision style: a click on one brings it to the front, F6
  # and Shift-F6 cycle them, Alt-1 … Alt-9 picks one by the number on its
  # frame. The active window has a double frame, the others a single one. A
  # +modal+ window (the Dialogs) keeps the front until it closes.
  #
  # A +maximizable+ window that can lay itself out at any size (#resizable?:
  # MasterDetail, Stream, Form, a scrolling Info) gets a zoom gadget in its
  # top right corner, Turbo Vision style: [↑] fills the desktop between the
  # menubar and the statusbar, [↕] puts it back. F5, Alt-Enter and a double
  # click on the title bar do the same.
  #
  # A window that is not maximized can be moved and, when resizable?,
  # resized (<tt>movable: false</tt> turns it off): drag the title bar to
  # move it, the bottom right corner to size it. From the keyboard Ctrl-F5
  # (or F6) starts it (F6 only while it is the only window), Turbo Vision
  # style: the arrows move the window, Shift and the arrows size it (Tab switches the arrows between moving and sizing), and
  # Enter or Esc ends it. A window moved or sized keeps its place when the
  # terminal is resized, pulled back onto the screen if needed.
  class Window < Container
    # Keys that toggle the maximized state of a zoomable window.
    ZOOM_KEYS    = %i[f5 alt_enter].freeze
    # Keys that start (and end) moving or sizing the window from the
    # keyboard.
    MOVE_KEYS    = %i[ctrl_f5 f6].freeze
    # Arrow key Symbol => <tt>[dx, dy]</tt> step for keyboard moving and
    # sizing.
    ARROWS       = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze
    # Seconds within which a second click on the title bar counts as a
    # double click.
    DOUBLE_CLICK = 0.5
    # Smallest width a resizable window can be sized to (or the desktop
    # width when that is smaller).
    MIN_WIDTH    = 24
    # Smallest height a resizable window can be sized to (or the desktop
    # height when that is smaller).
    MIN_HEIGHT   = 7
    # Titles shown in the frame while the window is moved (+:move+) or sized
    # (+:size+) from the keyboard.
    KBD_TITLES   = { move: ' Move: arrows · Shift+arrows or Tab: size · Enter: done ',
                     size: ' Size: arrows · Tab: move · Enter: done ' }.freeze
    # Width of a title bar gadget: <tt>[■]</tt>, <tt>[↑]</tt>.
    GADGET_WIDTH      = 3
    # Column of the close gadget, from the window's left edge.
    CLOSE_X           = 2
    # Column of the zoom gadget, counted back from the right edge.
    ZOOM_FROM_RIGHT   = 5
    # Column of the window number before the zoom gadget, counted back
    # from it.
    NUMBER_BEFORE_ZOOM = 3
    # Column of the window number without a zoom gadget, counted back from
    # the right edge.
    NUMBER_FROM_RIGHT = 4
    # Where the title starts when there is a close gadget.
    TITLE_INDENT      = 4
    # The narrowest window that shows the close gadget.
    CLOSE_MIN_WIDTH   = 6
    # The narrowest window that shows the zoom gadget.
    ZOOM_MIN_WIDTH    = 14
    # The narrowest window that shows its number.
    NUMBER_MIN_WIDTH  = 20
    # The narrowest window that shows the size corner.
    CORNER_MIN_WIDTH  = 6
    # Columns of the title bar a title gives up to the gadgets when there
    # is a zoom gadget.
    TITLE_ROOM_ZOOM   = 14
    # Columns of the title bar a title gives up without a zoom gadget.
    TITLE_ROOM        = 4
    # Further columns a title gives up to the window number.
    NUMBER_ROOM       = 4
    # Columns of the bottom right corner that start a size drag.
    CORNER_HIT        = 2

    # A Shift, Ctrl, Alt or Ctrl-Shift modified movement key; the group is
    # the key without the modifier.
    MODIFIED_MOVE_KEY = /\A(?:shift|ctrl|alt|ctrl_shift)_((?:page_)?(?:up|down)|left|right|home|end)\z/
    # An Alt-modified key name, <tt>alt_x</tt>; the group is the letter.
    ALT_KEY = /\Aalt_(.)\z/

    # The window's settings, as given to ::new: +title+ (shown in the top
    # border), +modal+ (keeps the front, always a double frame), +shadow+
    # (draws a drop shadow), +on_close+ (callable run with the window when it
    # closes, or +false+ for no close gadget), +close_key+ (key that closes
    # it), +maximizable+ (gets a zoom gadget when #resizable?), +movable+
    # (may be moved and sized). +number+ is the number shown on the frame for
    # Alt-1 ... Alt-9, assigned by the Application to non-modal windows.
    attr_accessor :title, :modal, :shadow, :on_close, :close_key, :maximizable, :movable, :number
    # Style roles of the window's own frame drawn in other colours than the
    # theme's, as a Hash of role => SGR (+:window_border+, +:window_title+,
    # +:window_title_focused+), or +nil+. The widgets inside keep the theme:
    # an accent marks which part of the board a window belongs to.
    #
    #   window.accent = { window_border: "\e[0;38;5;79;48;5;16m" }
    attr_accessor :accent
    # The Application the window is shown in; set by the Application when it
    # opens the window. Moving, sizing and zooming need it.
    attr_writer :app

    # Creates a window. +title+, +modal+, +shadow+, +on_close+,
    # +close_key+, +maximizable+ and +movable+ set the attributes of the same
    # name; +kw+ (+id+, +bounds+, +theme+) go to Container.new. The window
    # starts not maximized and without a number.
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
      @number      = nil
    end

    # Returns the SGR for the style role +key+: the #accent's when it has
    # one, else the theme's (see BBS::Widget#style).
    def style(key) = @accent&.[](key) || super

    # True while the window is being moved or sized: the keys are its own.
    def busy? = !@kbd_mode.nil? || !@drag.nil?

    # Returns whether the window fills the desktop.
    def maximized? = @maximized

    # True for windows that can lay out their content at any size; they
    # override <tt>place(x, y, width, height)</tt> and +normal_rect+.
    def resizable? = false

    # Returns whether the window can be maximized: it is +maximizable+,
    # #resizable? and shown in an Application.
    def zoomable? = @maximizable && resizable? && !@app.nil?

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

    # Returns whether the window can be moved now: +movable+, not maximized
    # and shown in an Application.
    def movable? = @movable && !@maximized && !@app.nil?
    # Returns whether the window can be sized now: #movable? and
    # #resizable?.
    def sizable? = movable? && resizable?

    # Moves (and, when resizable?, sizes) the window to the rect, kept on
    # the desktop; the window keeps it through later relayouts. A resizable
    # window is clamped to MIN_WIDTH by MIN_HEIGHT and the desktop size; any
    # other keeps its size. Does nothing unless #movable?.
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

    # Returns the window's FocusManager, created on first use.
    def focus_manager
      @focus_mgr ||= FocusManager.new(self)
    end

    # Replaces the FocusManager with a new one, so the focus starts over
    # from the window's current widgets.
    def reset_focus
      @focus_mgr = FocusManager.new(self)
    end

    # Draws the window into the BBS::FrameBuffer +frame+: the shadow (unless
    # maximized), the frame (double when focused or modal) with the title,
    # the close gadget <tt>[■]</tt>, the window number, the zoom gadget and
    # the size corner as they apply and fit, then the visible children.
    # While moving or sizing from the keyboard the title shows KBD_TITLES.
    def render(frame)
      if @shadow && !@maximized
        frame.shadow(x: bounds.x, y: bounds.y, width: bounds.width,
                     height: bounds.height, sgr: style(:window_shadow))
      end
      show_close  = @on_close != false && bounds.width >= CLOSE_MIN_WIDTH
      show_zoom   = zoomable? && bounds.width >= ZOOM_MIN_WIDTH
      show_number = @number && bounds.width >= NUMBER_MIN_WIDTH
      title       = @title
      room        = (show_zoom ? TITLE_ROOM_ZOOM : TITLE_ROOM) + (show_number ? NUMBER_ROOM : 0)
      title       = title.to_s[0, [bounds.width - room, 0].max] if show_zoom || show_number
      title = KBD_TITLES[@kbd_mode] if @kbd_mode
      frame.box(
        x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
        sgr: @kbd_mode || @drag ? style(:window_title_focused) : style(:window_border),
        fill_sgr: style(:window_bg), style: focused || @modal ? :double : :single, title: title,
        title_sgr: focused ? style(:window_title_focused) : style(:window_title),
        title_indent: show_close ? TITLE_INDENT : 0
      )
      # Close gadget — Turbo Vision style "[■]"
      if show_close
        frame.move(bounds.x + CLOSE_X, bounds.y)
        frame.write('[■]', sgr: style(:window_title))
      end
      if show_number
        frame.move(show_zoom ? zoom_x - NUMBER_BEFORE_ZOOM : bounds.x + bounds.width - NUMBER_FROM_RIGHT, bounds.y)
        frame.write(@number.to_s, sgr: focused ? style(:window_title_focused) : style(:window_title))
      end
      if show_zoom
        frame.move(zoom_x, bounds.y)
        frame.write(@maximized ? '[↕]' : '[↑]', sgr: style(:window_title))
      end
      if sizable? && bounds.width >= CORNER_MIN_WIDTH
        frame.move(bounds.x + bounds.width - 1, bounds.y + bounds.height - 1)
        frame.write('┘', sgr: style(:window_title))
      end
      @children.each { |c| c.render(frame) if c.visible }
    end

    # Returns +self+ for the close gadget area on the top border, otherwise
    # the deepest widget at +x+, +y+ as Container#hit_test does.
    def hit_test(x, y)
      # close gadget area
      if @on_close != false && y == bounds.y &&
         x >= bounds.x + CLOSE_X && x <= bounds.x + CLOSE_X + GADGET_WIDTH - 1
        return self
      end
      super
    end

    # Handles a keyboard or mouse event for the window, in this order:
    # keyboard move/size mode, an ongoing mouse drag, the ZOOM_KEYS and
    # MOVE_KEYS, left clicks on the gadgets, title bar and size corner (a
    # click elsewhere focuses the focusable widget under it), wheel events
    # for the widget under the pointer, focus keys and the focused widget
    # (a modified arrow or paging key nothing took is retried plain), a
    # button hotkey, and finally +close_key+.
    #
    # Returns +:close_window+ when the window should close, +:halt+ or
    # +:handled+ as the widgets return them, or +nil+ when nothing used the
    # event.
    def handle_event(event)
      return keyboard_move(event) if @kbd_mode
      return drag(event) if @drag && event.mouse?
      return toggle_maximize if event.key? && zoomable? && ZOOM_KEYS.include?(event.key)
      if event.key? && MOVE_KEYS.include?(event.key) && movable?
        @kbd_mode = :move
        return :handled
      end

      if event.mouse? && event.mouse.kind == :press && event.mouse.button == :left
        if @on_close != false && event.y == bounds.y && event.x >= bounds.x + CLOSE_X &&
           event.x <= bounds.x + CLOSE_X + GADGET_WIDTH - 1
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
      if result.nil? && event.key? && (plain = event.key.to_s[MODIFIED_MOVE_KEY, 1])
        result = focus_manager.dispatch(Event.key(plain.to_sym))
      end
      return result if result

      # A key the focused widget left alone presses the button it is the
      # hotkey of: "y" or Alt-Y for "&Yes".
      if event.key? && (button = hotkey_button(event.key))
        return button.fire
      end

      return close if event.key? && event.key == @close_key
      nil
    end

    # The Application closes the window and calls on_close (see
    # Application#close_window), so the callback runs once.
    def close = :close_window

    # Returns the column where the zoom gadget is drawn.
    def zoom_x = bounds.x + bounds.width - ZOOM_FROM_RIGHT

    # The zoom gadget, or a second click on the title bar soon after a first.
    def title_click?(event)
      return false unless event.y == bounds.y && event.x.between?(bounds.x, bounds.x + bounds.width - 1)
      return true if event.x.between?(zoom_x, zoom_x + GADGET_WIDTH - 1)

      now    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      double = @title_clicked_at && now - @title_clicked_at < DOUBLE_CLICK
      @title_clicked_at = double ? nil : now
      double
    end

    # Returns whether the mouse +event+ is on the bottom right size corner.
    def corner?(event)
      event.y == bounds.y + bounds.height - 1 && event.x >= bounds.x + bounds.width - CORNER_HIT &&
        event.x <= bounds.x + bounds.width - 1
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

    # Handles +event+ in keyboard move/size mode: the arrows move or (with
    # Shift, or in size mode) size the window by one cell, Tab switches
    # between moving and sizing when #sizable?, and Enter, Esc or a
    # MOVE_KEYS key ends the mode. Every key is swallowed: returns
    # +:handled+.
    def keyboard_move(event)
      return :handled unless event.key?

      key = event.key
      if %i[enter escape].include?(key) || MOVE_KEYS.include?(key)
        @kbd_mode = nil
      elsif key == :tab && sizable?
        @kbd_mode = @kbd_mode == :move ? :size : :move
      elsif (step = ARROWS[key.to_s.delete_prefix('shift_').to_sym])
        size = (@kbd_mode == :size || key.to_s.start_with?('shift_')) && sizable?
        x = bounds.x
        y = bounds.y
        w = bounds.width
        h = bounds.height
        size ? move_to(x, y, w + step[0], h + step[1]) : move_to(x + step[0], y + step[1], w, h)
      end
      :handled
    end

    # Returns the enabled Widgets::Button in the window whose hotkey matches
    # +key+ (a single character or an +alt_+ letter Symbol), or +nil+.
    def hotkey_button(key)
      letter = key.is_a?(String) && key.length == 1 ? key.downcase : key.to_s[ALT_KEY, 1]
      return nil unless letter

      focusable_descendants.find { |w| w.is_a?(Widgets::Button) && w.enabled && w.hotkey == letter }
    end

    # Called once per Application idle tick (about a second) with the
    # Application. Does nothing; subclasses that poll for asynchronous
    # updates override it (such as BBS::Windows::Stream).
    def tick(app); end

    # Called by the Application when the terminal is resized. The default
    # keeps the window's size and re-centers it, shifting every descendant
    # along. Subclasses whose geometry depends on the terminal size override
    # this (such as BBS::Windows::MasterDetail). A window moved or sized by
    # the user goes back to its place, a resizable one is placed at the
    # desktop (maximized) or its +normal_rect+.
    def relayout(app)
      return move_to(*@placed) if @placed && !@maximized
      return place(*(@maximized ? app.desktop_rect : normal_rect)) if resizable?

      dx = [((app.cols - bounds.width) / 2) + 1, 1].max - bounds.x
      dy = [((app.rows - bounds.height) / 2) + 1, 1].max - bounds.y
      shift(dx, dy)
    end

    # Moves the window and all its descendants by +dx+ columns and +dy+
    # rows.
    def shift(dx, dy)
      return if dx.zero? && dy.zero?
      walk do |w|
        b = w.bounds
        w.bounds = Widget::Rect.new(b.x + dx, b.y + dy, b.width, b.height)
      end
    end
  end
end
