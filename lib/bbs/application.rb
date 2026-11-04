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
require_relative 'application/announcements'
require_relative 'application/screen'
require_relative 'application/builder'
require_relative 'application/conveniences'
require_relative 'paint'

module BBS
  # A windowed face: the desktop, a menubar, the statusbar and a stack of
  # windows, drawn with a theme and driven by keys and the mouse. Declared
  # with Application.define (see Builder) and run by BBS.board or a Flow's
  # +app+ step:
  #
  #   UI::Modern = BBS::Application.define do
  #     theme :synchronet
  #     command :search, 'Search…', key: 'F2' do search end
  #     menu 'Wiki', :search, :separator, :log_off
  #     help about: ABOUT
  #     status { "#{lang}.wikipedia.org" }
  #     desktop { on_show { search } }
  #     window(:results, :master_detail) { items { results }; label :title }
  #   end
  #
  # The blocks of the declaration run in the Application: the helpers, the
  # services (as readers), and the methods below (Conveniences: #message,
  # #ask, #confirm, #loading, #qr, #show, the colours of BBS::Paint …).
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

    # [session]      the BBS::Session the application draws on and reads from
    # [session_id]   the session's id
    # [context]      the caller's context Hash, shared with the flow and doors
    # [root]         the root BBS::Container behind all windows
    # [menubar]      the BBS::Menubar, or +nil+
    # [statusbar]    the BBS::Statusbar, or +nil+
    # [windows]      the open windows, bottom to top (the last is in front)
    # [theme]        the BBS::Theme every widget is drawn with
    # [services]     Hash of the service objects by name
    # [window_specs] Hash of the declared BBS::WindowSpec objects by name
    # [doors]        Hash of the declared BBS::Door objects by name
    attr_reader :session, :session_id, :context, :root, :menubar, :statusbar,
                :windows, :theme, :services, :window_specs, :doors

    # The desktop widget (BBS::Widgets::Desktop), or +nil+.
    attr_accessor :desktop

    include WindowStack
    include EventLoop
    include Announcements
    include Screen
    include Conveniences
    include Paint

    # Evaluates the DSL +block+ in a new Builder and returns the Builder;
    # its +run+ (or BBS.board, or a Flow's +app+ step) runs the application.
    def self.define(&block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      builder
    end

    # Creates an application on +session+. Usually Builder#build makes it.
    #
    # [context]      the caller's context Hash
    # [theme]        the BBS::Theme; default <tt>BBS.config.theme</tt>, else
    #                BBS::Theme.synchronet
    # [on_idle]      callable run with the application at the idle limit
    # [on_tick]      callable run with the application once a second
    # [helpers]      a Module of helper methods the application is extended with
    # [services]     Hash of service objects; each gets a reader of its name
    #                unless the application has such a method already
    # [window_specs] Hash of BBS::WindowSpec by name
    # [doors]        Hash of BBS::Door by name
    # [status]       block whose text is the right end of the statusbar
    # [clock]        whether the time follows it
    def initialize(session:, session_id:, context: {}, theme: nil, on_idle: nil, on_tick: nil, helpers: nil,
                   services: {}, window_specs: {}, doors: {}, status: nil, clock: false)
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
      @status       = status
      @clock        = clock
      extend(helpers) if helpers
      define_service_readers
    end

    # The terminal's width in columns (NAWS), 80 when it did not say.
    def cols = @session.term_cols || Telnet::DEFAULT_COLS

    # The terminal's height in rows (NAWS), 24 when it did not say.
    def rows = @session.term_rows || Telnet::DEFAULT_ROWS

    # Sets the menubar, giving it the application's theme.
    def menubar=(menubar)
      @menubar = menubar
      menubar.theme = @theme if menubar
    end

    # Sets the statusbar, giving it the application's theme.
    def statusbar=(statusbar)
      @statusbar = statusbar
      statusbar.theme = @theme if statusbar
    end

    # Adds +child+ to the root container behind the windows, with the
    # application's theme. Returns +child+.
    def add(child)
      @root.add(child)
      child.theme = @theme
      child
    end

    # Leaves through the declared door +name+: Builder#run opens it once the
    # application has stopped. Returns +:halt+. Raises ArgumentError for an
    # unknown door.
    def open_door(name)
      door = @doors[name.to_sym]
      raise ArgumentError, "Unknown door: #{name.inspect}" unless door

      @context[:door] = door
      stop!
      :halt
    end

    # The board's domain object (BBS::Config#board).
    def board = BBS.config.board

    # Keeps a caller who reached the idle limit on the line (called from the
    # +on_idle+ block, after a "still there?" got an answer); the idle time
    # starts again.
    def keep_on = (@kept_on = true)

    # Ends the call's application: the flow goes on to the goodbye. Returns
    # +:halt+.
    def log_off
      stop!
      :halt
    end

    # Writes the right end of the statusbar: the status block's text and
    # the clock.
    def refresh_status
      return unless @statusbar

      text  = @status && instance_exec(&@status)
      clock = Time.now.strftime('%H:%M') if @clock
      parts = @clock == :before ? [clock, text] : [text, clock]
      @statusbar.right_text = parts.compact.join(' │ ')
    end

    # Hands the raw line to the block (a file transfer, a gateway) on a
    # clean screen without mouse reporting (BBS::Session#hand_over), then
    # repaints everything. Returns the block's value.
    def with_line(&)
      @session.hand_over(&)
    ensure
      @committed = nil
    end

    private

    def define_service_readers
      @services.each do |name, service|
        define_singleton_method(name) { service } unless respond_to?(name, true)
      end
    end
  end
end
