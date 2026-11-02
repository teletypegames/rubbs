# frozen_string_literal: true

require_relative 'event'
require_relative 'theme'
require_relative 'frame_buffer'
require_relative 'widget'
require_relative 'container'
require_relative 'window'
require_relative 'widgets'
require_relative 'menu'
require_relative 'statusbar'
require_relative 'dialogs'
require_relative 'window_spec'
require_relative 'door'
require_relative 'application/window_stack'
require_relative 'application/event_loop'
require_relative 'application/screen'
require_relative 'application/builder'

module BBS
  # The widget event loop. Acts as the root container:
  #
  #   root_panel        — base UI (drawn behind windows)
  #   menubar           — optional, Alt-letter pulldown menus
  #   statusbar         — optional, hotkey hints at the bottom
  #   window stack      — modal windows on top of root_panel
  #
  # Build one with Application.define { ... } DSL, or instantiate directly
  # and use add_window / menubar / statusbar.
  #
  # Doors (BBS::Door) are declared in the DSL and opened from any handler;
  # Builder#run then hands the line to the door and rebuilds the
  # application when the caller comes back:
  #
  #   APP = BBS::Application.define do
  #     door :sermo, Sermo::OS, label: '&SERMO'
  #     menubar do
  #       menu('&Doors') { doors }        # one item per declared door
  #     end
  #   end
  #
  #   APP.run(session: session, session_id: sid, context: ctx)
  class Application
    # The window numbers handed out, shown in the frame and picked with
    # Alt-1 ... Alt-9.
    WINDOW_NUMBERS = 1..9
    # The sort key of a window without a number: after every numbered one.
    UNNUMBERED = 10
    # Rows the menubar and the statusbar each take.
    BAR_HEIGHT = 1
    # The fewest rows the desktop between the bars is given.
    MIN_DESKTOP_ROWS = 3
    # Seconds between two #tick! calls while no key comes.
    TICK_SECONDS = 1.0
    # Seconds the idle disconnect message stays before the line is dropped.
    IDLE_MESSAGE_WAIT = 0.5
    # Lines of the backtrace logged with a handler's error.
    BACKTRACE_LINES = 3
    # Columns the "Please wait" box of #with_loading takes beside its text.
    LOADING_CHROME = 8

    # [session]      the BBS::Session the application draws on and reads from
    # [session_id]   the session's id
    # [context]      the caller's context Hash, shared with the flow and doors
    # [root]         the root BBS::Container behind all windows
    # [menubar]      the BBS::Menubar, or +nil+
    # [statusbar]    the BBS::Statusbar, or +nil+
    # [windows]      the open windows, bottom to top (the last is in front)
    # [theme]        the BBS::Theme every widget is drawn with
    # [services]     Hash of service objects handed to window callbacks
    # [window_specs] Hash of the registered BBS::WindowSpec objects by name
    # [doors]        Hash of the declared BBS::Door objects by name
    attr_reader :session, :session_id, :context, :root, :menubar, :statusbar,
                :windows, :theme, :services, :window_specs, :doors

    include WindowStack
    include EventLoop
    include Screen

    # Evaluates the DSL +block+ in a new Builder and returns the Builder;
    # call <tt>Builder#run</tt> (or <tt>Builder#build</tt>) on it for each
    # session.
    def self.define(&block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      builder
    end

    # Creates an application with no windows, menubar or statusbar.
    #
    # [session]      the BBS::Session to run on
    # [session_id]   the session's id
    # [context]      the caller's context Hash
    # [theme]        the BBS::Theme; default <tt>BBS.config.theme</tt>, or
    #                BBS::Theme.synchronet when that is not set either
    # [on_idle]      callable invoked as <tt>call(app)</tt> when the caller
    #                reaches the idle limit (see #run); returning +:keep+
    #                keeps the caller on and starts the count again
    # [on_tick]      callable invoked as <tt>call(app)</tt> on every tick (see
    #                #tick!)
    # [helpers]      a Module the application is extended with
    # [services]     Hash of service objects for window callbacks
    # [window_specs] Hash of BBS::WindowSpec objects by name, for #open_window
    # [doors]        Hash of BBS::Door objects by name, for #open_door
    def initialize(session:, session_id:, context: {}, theme: nil, on_idle: nil,
                   on_tick: nil, helpers: nil, services: {}, window_specs: {}, doors: {})
      @session      = session
      @session_id   = session_id
      @context      = context
      @theme        = theme || BBS.config.theme || Theme.synchronet
      @root         = Container.new.tap { |root| root.theme = @theme }
      @windows      = []
      @on_idle      = on_idle
      @on_tick      = on_tick
      @services     = services
      @window_specs = window_specs
      @doors        = doors
      extend(helpers) if helpers
    end

    # The terminal width in columns (80 when the session does not know it).
    def cols = @session.term_cols || Telnet::DEFAULT_COLS
    # The terminal height in rows (24 when the session does not know it).
    def rows = @session.term_rows || Telnet::DEFAULT_ROWS

    # Sets the BBS::Menubar shown on the top row (or +nil+ for none) and
    # gives it the application's theme.
    def menubar=(menubar)
      @menubar = menubar
      menubar.theme = @theme if menubar
    end

    # Sets the BBS::Statusbar shown on the bottom row (or +nil+ for none) and
    # gives it the application's theme.
    def statusbar=(statusbar)
      @statusbar = statusbar
      statusbar.theme = @theme if statusbar
    end

    # Adds the widget +child+ to the root container, behind all windows, and
    # gives it the application's theme. Returns +child+.
    def add(child)
      @root.add(child)
      child.theme = @theme
      child
    end

    # Leaves the application through a declared door, from any handler: a
    # menu item, a key, a window button or a list's Enter. The event loop
    # stops after this event, and Builder#run opens the door. Stores the door
    # under <tt>context[:door]</tt>. Returns :halt, so a handler can also end
    # with it. Raises ArgumentError for an unknown door name.
    def open_door(name)
      door = @doors[name.to_sym]
      raise ArgumentError, "Unknown door: #{name.inspect}" unless door

      @context[:door] = door
      stop!
      :halt
    end

    # Hands the raw line to the block, a file transfer for one, on a clean
    # screen without mouse reporting, and repaints the whole application
    # when it returns. Returns what the block returns.
    def with_line
      @session.disable_mouse
      @session.write("#{Ansi::RESET}#{Ansi::CLEAR}")
      yield @session
    ensure
      @session.enable_mouse if BBS.config.mouse
      @committed = nil
    end

    # Shows a "Please wait" message with +text+, runs the block in a thread
    # and waits for it, then closes the message. Returns the block's value.
    def with_loading(text = 'Working...', &block)
      win = Dialogs.message(self, text, title: ' Please wait ', width: text.length + LOADING_CHROME)
      render_screen
      Thread.new do
        @loading_result = block.call
      ensure
        close_window(win)
      end.join
      @loading_result
    end
  end
end
