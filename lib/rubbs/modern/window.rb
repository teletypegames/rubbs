# frozen_string_literal: true

require_relative 'widgets/container'
require_relative 'widgets/focus_manager'
require_relative 'window/frame'
require_relative 'window/placement'
require_relative 'window/events'

module Rubbs
  module Modern
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
    class Window < Widgets::Container
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
      KBD_TITLES   = {
        move: ' Move: arrows · Shift+arrows or Tab: size · Enter: done ',
        size: ' Size: arrows · Tab: move · Enter: done '
      }.freeze
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

      include Frame
      include Placement
      include Events

      # Creates a window. +title+, +modal+, +shadow+, +on_close+,
      # +close_key+, +maximizable+ and +movable+ set the attributes of the same
      # name; +kw+ (+id+, +bounds+, +theme+) go to Container.new. The window
      # starts not maximized and without a number.
      def initialize(
        title: nil,
        modal: false,
        shadow: true,
        on_close: nil,
        close_key: :escape,
        maximizable: false,
        movable: true,
        **kw
      )
        super(**kw)
        @title       = title
        @modal       = modal
        @shadow      = shadow
        @on_close    = on_close
        @close_key   = close_key
        @maximizable = maximizable
        @movable     = movable
        @maximized   = false
        @placed = @drag = @kbd_mode = @focus_manager = @number = nil
      end

      # Returns the SGR for the style role +key+: the #accent's when it has
      # one, else the theme's (see Rubbs::Modern::Widgets::Widget#style).
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

      # Returns whether the window can be moved now: +movable+, not maximized
      # and shown in an Application.
      def movable? = @movable && !@maximized && !@app.nil?
      # Returns whether the window can be sized now: #movable? and
      # #resizable?.
      def sizable? = movable? && resizable?

      # Returns the window's FocusManager, created on first use.
      def focus_manager
        @focus_manager ||= Widgets::FocusManager.new(self)
      end

      # Replaces the FocusManager with a new one, so the focus starts over
      # from the window's current widgets.
      def reset_focus
        @focus_manager = Widgets::FocusManager.new(self)
      end

      # Returns +self+ for the close gadget area on the top border, otherwise
      # the deepest widget at +x+, +y+ as Container#hit_test does.
      def hit_test(x, y)
        close_gadget_at?(x, y) ? self : super
      end

      # The Application closes the window and calls on_close (see
      # Application#close_window), so the callback runs once.
      def close = :close_window

      # Called once per Application idle tick (about a second) with the
      # Application. Does nothing; subclasses that poll for asynchronous
      # updates override it (such as Rubbs::Modern::Windows::Stream).
      def tick(app); end
    end
  end
end
