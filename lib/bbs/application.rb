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
      @session       = session
      @session_id    = session_id
      @context       = context
      @theme         = theme || BBS.config.theme || Theme.synchronet
      @root          = Container.new
      @root.theme    = @theme
      @menubar       = nil
      @statusbar     = nil
      @windows       = []
      @running       = false
      @committed     = nil
      @on_idle       = on_idle
      @on_tick       = on_tick
      @helpers       = helpers
      @services      = services
      @window_specs  = window_specs
      @doors         = doors
      extend(@helpers) if @helpers
    end

    # The terminal width in columns (80 when the session does not know it).
    def cols = @session.term_cols || 80
    # The terminal height in rows (24 when the session does not know it).
    def rows = @session.term_rows || 24

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

    # Opens a window and puts it in front with the focus.
    #
    # [target] a Symbol or String naming a registered BBS::WindowSpec, or a
    #          BBS::Window to push onto the window stack as it is
    # [extras] keyword arguments passed into the spec's callback +ctx+
    #
    # A non-modal Window gets the lowest free number from 1 to 9 (for
    # Alt-digit switching). Returns the opened window. Raises ArgumentError
    # for an unknown spec name.
    def open_window(target, **extras)
      if target.is_a?(Symbol) || target.is_a?(String)
        spec = @window_specs[target.to_sym]
        raise ArgumentError, "Unknown window: #{target.inspect}" unless spec
        spec.open(self, **extras)
      else
        target.theme  = @theme
        target.app    = self
        target.number = free_number unless target.modal
        top_window&.focused = false
        @windows << target
        target.focused = true
        target
      end
    end

    # Brings an open window to the front and makes it the active one.
    # Returns +window+; a window that is not open is left alone.
    def raise_window(window)
      return window if window == top_window || !@windows.include?(window)

      top_window.focused = false
      @windows.delete(window)
      @windows << window
      window.focused = true
      window
    end

    # Returns the windows the caller can switch between, sorted by their
    # number. Empty while a modal window (a dialog) is open: it keeps the
    # front.
    def switchable_windows
      return [] if @windows.any?(&:modal)

      @windows.reject(&:modal).sort_by { |w| w.number || 10 }
    end

    # Brings the next (+step+ 1, F6) or previous (+step+ -1, Shift-F6)
    # switchable window to the front, by number. Returns the raised window,
    # or +nil+ when fewer than two windows can be switched.
    def cycle_windows(step = 1)
      list = switchable_windows
      return nil if list.size < 2

      index = list.index(top_window) || 0
      raise_window(list[(index + step) % list.size])
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

    # True when the run ended because the line did (a hang-up, the idle
    # limit): no door is opened after it.
    def line_lost? = @line_lost == true

    # Hands the raw line to the block, a file transfer for one, on a clean
    # screen without mouse reporting, and repaints the whole application
    # when it returns. Returns what the block returns.
    def with_line
      @session.disable_mouse
      @session.write("\e[0m\e[2J\e[H")
      yield @session
    ensure
      @session.enable_mouse if BBS.config.mouse
      @committed = nil
    end

    # Removes +window+ (default: the top one) from the window stack, gives
    # the focus to the new top window and calls the window's +on_close+ with
    # it when that is callable. Returns +nil+ when no window is open.
    def close_window(window = nil)
      window ||= @windows.last
      return unless window
      @windows.delete(window)
      window.focused = false
      top_window&.focused = true
      window.on_close.call(window) if window.on_close.respond_to?(:call)
    end

    # The window in front, or +nil+ when none is open.
    def top_window
      @windows.last
    end

    # The screen between the menubar and the statusbar, as [x, y, w, h]:
    # where a maximized window goes.
    def desktop_rect
      top    = @menubar ? 1 : 0
      bottom = @statusbar ? 1 : 0
      [1, 1 + top, cols, [rows - top - bottom, 3].max]
    end

    # Main event loop. Uses a short read timeout to fire periodic ticks for
    # UI polling (chat, clock) while still detecting hard idle disconnects.
    #
    # Draws the screen, reads a key with a one-second timeout and dispatches
    # it as a BBS::Event: an open menubar first, then window switching keys,
    # the top window, the menubar, the statusbar and the root container's
    # focused widget. A second without input calls #tick!. After the idle
    # limit without input (the session's +idle_seconds+, set from
    # BBS.config.idle_seconds) the +on_idle+ callable runs; unless it
    # returns +:keep+, the loop shows a message and ends.
    # A handler's StandardError is logged and the loop goes on. Ends when a
    # handler returns :halt, #stop! is called or the line drops (see
    # #line_lost?), then shows the cursor and clears the screen.
    def run
      @running     = true
      idle_max     = idle_limit
      tick_seconds = 1.0
      idle_elapsed = 0.0
      while @running
        do_render
        key = @session.readkey(timeout: tick_seconds)
        if key.nil?
          @line_lost = true
          break
        end

        if key == :idle
          idle_elapsed += tick_seconds
          tick!
          if idle_max && idle_elapsed >= idle_max
            if @on_idle&.call(self) == :keep
              idle_elapsed = 0.0
              idle_max     = idle_limit
              next
            end
            BBS::Dialogs.message(self, "Disconnected after #{idle_max.to_i}s idle.",
                                 title: ' Idle ')
            do_render
            sleep 0.5
            @line_lost = true
            break
          end
          next
        end

        idle_elapsed = 0.0
        event  = build_event(key)
        result = begin
          dispatch(event)
        rescue IOError, SystemCallError
          raise
        rescue StandardError => e
          # One handler's fault must not end the caller's whole session.
          warn "BBS event error: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
          nil
        end
        break if result == :halt
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      @line_lost = true
      nil
    ensure
      @session.write("\e[?25h\e[2J\e[H")
      @running = false
    end

    # The idle limit in seconds for this run: the session's +idle_seconds+
    # when it has one, else BBS.config.idle_seconds; +nil+ means no limit.
    def idle_limit
      @session.respond_to?(:idle_seconds) ? @session.idle_seconds : BBS.config.idle_seconds
    end

    # Periodic tick: notify on_tick callback and let each open window pull
    # any asynchronous updates by overriding BBS::Window#tick.
    def tick!
      @on_tick&.call(self)
      @windows.each { |w| w.tick(self) }
    end

    # Makes the event loop end after the current event.
    def stop! = (@running = false)

    # Shows a "Please wait" message with +text+, runs the block in a thread
    # and waits for it, then closes the message. Returns the block's value.
    def with_loading(text = 'Working...', &block)
      win = Dialogs.message(self, text, title: ' Please wait ', width: text.length + 8)
      do_render
      Thread.new do
        begin
          @loading_result = block.call
        ensure
          close_window(win)
        end
      end.join
      @loading_result
    end

    private

    def build_event(key)
      case key
      when Telnet::MouseEvent then Event.mouse(key)
      when :idle              then Event.idle
      else                          Event.key(key)
      end
    end

    def dispatch(event)
      # An open menubar has priority — its keys (arrows, Enter, hotkeys, Esc)
      # must beat any modal window's focused widget. Always swallow events
      # while the menu is open so they cannot leak through to windows.
      if @menubar&.open?
        result = @menubar.handle_event(event)
        return :halt if result == :halt
        return nil
      end

      return nil if switch_windows(event)

      # The top window gets first shot at events
      if (win = top_window)
        result = win.handle_event(event)
        return :halt if result == :halt
        if result == :close_window
          close_window(win)
          return nil
        end
        return nil if result
      end

      # Menubar handles Alt-letter / F10 / its own keys when closed
      if @menubar
        result = @menubar.handle_event(event)
        return :halt if result == :halt
        return nil if result
      end

      # Statusbar mouse clicks
      if @statusbar
        result = @statusbar.handle_event(event)
        return :halt if result == :halt
        return nil if result
      end

      # Root panel (background UI) — try its focused widget
      result = dispatch_to_root(event)
      return :halt if result == :halt
      result
    end

    # F6, Shift-F6 and Alt-digit switch windows; a click on a window behind
    # the top one brings it to the front, and the click goes on to it, so a
    # button or the title bar answers at once. True when a key was taken.
    def switch_windows(event)
      return false if top_window&.busy?

      if event.key?
        case event.key
        when :f6       then return !cycle_windows(1).nil?
        when :shift_f6 then return !cycle_windows(-1).nil?
        when :alt_1, :alt_2, :alt_3, :alt_4, :alt_5, :alt_6, :alt_7, :alt_8, :alt_9
          number = event.key.to_s[-1].to_i
          target = switchable_windows.find { |w| w.number == number }
          return false unless target

          raise_window(target)
          return true
        end
      elsif event.mouse? && event.mouse.kind == :press && !@menubar&.open?
        list   = switchable_windows
        target = @windows.reverse.find { |w| w.bounds.contains?(event.x, event.y) }
        raise_window(target) if target && list.include?(target)
      end
      false
    end

    def free_number
      taken = @windows.filter_map(&:number)
      (1..9).find { |n| !taken.include?(n) }
    end

    def dispatch_to_root(event)
      @root_focus ||= FocusManager.new(@root)
      return :handled if @root_focus.handle_focus_key(event)
      @root_focus.dispatch(event)
    end

    def relayout!
      c = cols
      r = rows

      menubar_h   = @menubar   ? 1 : 0
      statusbar_h = @statusbar ? 1 : 0

      @menubar&.layout(1, 1, c, 1)
      @statusbar&.layout(1, r, c, 1)
      @root.layout(1, 1 + menubar_h, c, r - menubar_h - statusbar_h)
    end

    def do_render
      c = cols
      r = rows
      first = @committed.nil?
      resized = !first && (@committed.cols != c || @committed.rows != r)
      @committed = FrameBuffer.new(c, r) if first || resized
      @next      = FrameBuffer.new(c, r)

      relayout!
      @windows.each { |w| w.relayout(self) } if resized

      @next.fill(x: 1, y: 1, width: c, height: r, sgr: @theme[:screen])
      @root.render(@next)
      @windows.each { |w| w.render(@next) }
      @menubar&.render(@next)
      @statusbar&.render(@next)

      delta = @next.diff(@committed)
      if first || resized || !delta.empty?
        prefix = (first || resized) ? "\e[2J\e[H" : ''
        @session.write("\e[?25l#{prefix}#{delta}\e[?25h")
        @committed = @next
      end
    end

    # ── Builder DSL ───────────────────────────────────────────────────────────
    # The DSL of Application.define. Its methods record the application's
    # parts; #build makes an Application from them for one session, and #run
    # runs it with its doors.
    class Builder
      # [init_block]      the #init block, or +nil+
      # [theme]           the BBS::Theme set with #theme, or +nil+
      # [menubar_block]   the #menubar block, or +nil+
      # [statusbar_hints] the #status_hint entries, as
      #                   <tt>[key, label, block, hidden]</tt> Arrays
      # [helper_module]   the Module the #helpers blocks define methods in
      # [window_specs]    Hash of the #window specs by name
      # [doors]           Hash of the #door objects by name
      attr_reader :init_block, :theme, :menubar_block, :statusbar_hints,
                  :helper_module, :window_specs, :doors

      # Creates an empty Builder; Application.define makes one.
      def initialize
        @init_block      = nil
        @theme           = nil
        @menubar_block   = nil
        @statusbar_hints = []
        @body_block      = nil
        @helper_module   = Module.new
        @services        = {}
        @window_specs    = {}
        @doors           = {}
        @tick_block      = nil
        @idle_block      = nil
        @door_block      = nil
      end

      # Declares a door: +program+ is a BBS::FakeOS definition, a BBS::Flow
      # or a callable <tt>call(session, context)</tt>; +label+ is its menu
      # item (default: the upcased name). Returns the BBS::Door. Raises
      # ArgumentError when +program+ is none of these.
      def door(name, program, label: nil)
        @doors[name.to_sym] = Door.new(name, program, label: label)
      end

      # Merges +hash+ into the services handed to window callbacks and returns
      # the merged Hash. Without an argument returns the services so far.
      def services(hash = nil)
        return @services if hash.nil?
        @services = @services.merge(hash)
      end

      # Registers a BBS::WindowSpec of +type+ (+:info+, +:form+,
      # +:master_detail+ or +:stream+) under +name+, for
      # <tt>Application#open_window</tt>. The block gets the spec to
      # configure. Returns the spec.
      def window(name, type:, &block)
        spec = WindowSpec.new(name, type: type)
        block&.call(spec)
        @window_specs[name] = spec
        spec
      end

      # Sets the application's theme: <tt>theme BBS::Theme.dosnavigator</tt>,
      # <tt>theme :dosnavigator</tt>, or either with a block that overrides
      # roles (evaluated in a ThemeBuilder; a block alone starts from
      # <tt>BBS.config.theme</tt>, or BBS::Theme.synchronet). Without
      # arguments it returns the theme set so far. With no #theme call at all
      # the application gets <tt>BBS.config.theme</tt> (see Application.new).
      def theme(base = nil, &block)
        return @theme if base.nil? && block.nil?

        if block
          starting = case base
                     when Symbol then Theme.public_send(base)
                     when Theme  then base
                     when nil    then BBS.config.theme || Theme.synchronet
                     else             base
                     end
          builder = ThemeBuilder.new(starting)
          builder.instance_eval(&block)
          @theme = builder.build
        else
          @theme = base.is_a?(Symbol) ? Theme.public_send(base) : base
        end
      end

      # Sets the block run on the new application (with +self+ the
      # Application) each time #build makes one, after the menubar and
      # statusbar and before #body.
      def init(&block) = (@init_block = block)

      # Runs on the application (like a menu item) once a second while the
      # caller is idle: a clock, a counter on the statusbar, a poll.
      def on_tick(&block) = (@tick_block = block)

      # Runs on the application when the caller reaches the idle limit,
      # before the line is dropped. Return +:keep+ to keep the caller on (a
      # "still there?" dialog that got an answer); anything else ends the run.
      def on_idle(&block) = (@idle_block = block)

      # Runs with the door and the context just before Builder#run hands the
      # line to a door: who is where, a log line.
      def on_door(&block) = (@door_block = block)
      # Evaluates the block in the helper module: the methods it defines
      # become methods of every Application this builder makes.
      def helpers(&block) = @helper_module.module_eval(&block)
      # Sets the block that builds the menubar, evaluated in a
      # MenubarBuilder.
      def menubar(&block) = (@menubar_block = block)

      # Adds a statusbar hint for +key+ (a key Symbol such as +:f1+) with
      # +label+. The block runs on the application when the key is pressed
      # or the hint clicked. A +hidden+ hint is a key binding that takes no
      # room on the statusbar.
      def status_hint(key, label, hidden: false, &on_activate)
        @statusbar_hints << [key, label, on_activate, hidden]
      end

      # Sets the block that fills the root container, evaluated in a
      # BodyContext each time #build makes an application.
      def body(&block)
        @body_block = block
      end

      # Makes an Application for +session+ from the recorded parts: theme
      # (default <tt>BBS.config.theme</tt>, then BBS::Theme.synchronet),
      # helpers, services, window specs, doors, on_tick, on_idle, menubar and
      # statusbar, then runs the #init and #body
      # blocks. Returns the Application, not yet running.
      def build(session:, session_id:, context: {})
        app = Application.new(
          session: session, session_id: session_id, context: context,
          theme: @theme,
          helpers: @helper_module,
          services: @services,
          window_specs: @window_specs,
          doors: @doors,
          on_tick: @tick_block && ->(a) { a.instance_exec(&@tick_block) },
          on_idle: @idle_block && ->(a) { a.instance_exec(&@idle_block) }
        )
        if @menubar_block
          menubar_widget = Menubar.new
          menubar_widget.theme = app.theme
          menubar_builder = MenubarBuilder.new(menubar_widget, app)
          menubar_builder.instance_eval(&@menubar_block)
          app.menubar = menubar_widget
        end
        unless @statusbar_hints.empty?
          sb = Statusbar.new
          sb.theme = app.theme
          @statusbar_hints.each do |k, l, blk, hidden|
            wrapped = blk ? ->{ app.instance_exec(&blk) } : ->{ nil }
            sb.add_hint(k, l, hidden: hidden, &wrapped)
          end
          app.statusbar = sb
        end
        app.instance_exec(&@init_block) if @init_block
        if @body_block
          ctx = BodyContext.new(app)
          ctx.instance_exec(&@body_block)
        end
        app
      end

      # Builds and runs the application. When the caller leaves it through a
      # door, runs the door and builds the application again; returns when
      # the caller leaves without one or the line drops. The context lives
      # through it all. Calls the #on_door block before each door.
      def run(session:, session_id:, context: {})
        loop do
          app = build(session: session, session_id: session_id, context: context)
          app.run
          door = context.delete(:door)
          break if door.nil? || app.line_lost?

          @door_block&.call(door, context)
          door.run(session, context)
        end
      end
    end

    # DSL inside <tt>menubar do ... end</tt>.
    class MenubarBuilder
      # Wraps the BBS::Menubar to fill and the Application its items act on.
      def initialize(menubar, app)
        @menubar = menubar
        @app     = app
      end

      # Adds a pulldown menu titled +label+ (an <tt>&</tt> marks its Alt
      # hotkey). The block is evaluated in an ItemsBuilder to add the items.
      def menu(label, &block)
        items_builder = ItemsBuilder.new(@app)
        items_builder.instance_eval(&block) if block
        @menubar.menus << Menubar::Menu.new(label: label, items: items_builder.items, x: nil)
      end
    end

    # DSL inside <tt>menu(label) do ... end</tt>: collects the menu's items.
    class ItemsBuilder
      # The BBS::Menubar::MenuItem objects added so far.
      attr_reader :items

      # Creates an empty item list whose blocks run on +app+.
      def initialize(app)
        @app   = app
        @items = []
      end

      # Adds an item titled +label+, with an optional +shortcut+ text shown
      # beside it. The block runs on the application, with the item as its
      # argument, when the item is chosen.
      #
      # +enabled+ is true, false, or a lambda the application answers each
      # time the menu is drawn or used:
      #
      #   item('&Save', enabled: -> { current_doc }) { save }
      def item(label, shortcut: nil, enabled: true, &block)
        if enabled.is_a?(Proc)
          check   = enabled
          enabled = -> { @app.instance_exec(&check) }
        end
        @items << Menubar::MenuItem.new(
          label: label, shortcut: shortcut, enabled: enabled, separator: false,
          on_select: block ? ->(item) { @app.instance_exec(item, &block) } : nil
        )
      end

      # Adds a separator line between items.
      def separator
        @items << Menubar::MenuItem.new(label: '', shortcut: nil, enabled: false,
                                        separator: true, on_select: nil)
      end

      # One item per declared door, in declaration order.
      def doors
        @app.doors.each_value do |door|
          item(door.label) { open_door(door.name) }
        end
      end
    end

    # The object the Builder#body block is evaluated in.
    class BodyContext
      # Wraps +app+, the Application being built.
      def initialize(app)
        @app = app
      end

      # Adds +widget+ to the application's root container (see
      # Application#add). Returns +widget+.
      def add(widget) = @app.add(widget)
      # The Application being built.
      def app         = @app
    end

    # DSL inside `theme do ... end`. Any unknown method call with one argument
    # is treated as a style override (e.g. <tt>screen "\e[0m"</tt>).
    class ThemeBuilder
      # Starts from +base+, a BBS::Theme, with no overrides.
      def initialize(base)
        @base      = base
        @overrides = {}
      end

      # Replaces the base theme with +theme+, a BBS::Theme or the name of one
      # of its presets (a Symbol such as +:dosnavigator+).
      def inherit(theme)
        @base = theme.is_a?(Symbol) ? Theme.public_send(theme) : theme
      end

      # Overrides the style of role +key+ with +value+, an SGR escape
      # sequence.
      def style(key, value)
        @overrides[key.to_sym] = value
      end

      # Returns the base theme, or a copy of it with the overrides merged in.
      def build
        @overrides.empty? ? @base : @base.merge(@overrides)
      end

      # True for every name: any method can be a style override.
      def respond_to_missing?(_name, _include_private = false) = true

      # Treats <tt>role value</tt> as <tt>style(role, value)</tt>. Calls with
      # another number of arguments raise NoMethodError.
      def method_missing(name, *args)
        return @overrides[name] = args.first if args.size == 1
        super
      end
    end
  end
end
