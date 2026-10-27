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
    attr_reader :session, :session_id, :context, :root, :menubar, :statusbar,
                :windows, :theme, :services, :window_specs, :doors

    def self.define(&block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      builder
    end

    def initialize(session:, session_id:, context: {}, theme: nil, on_idle: nil,
                   on_tick: nil, helpers: nil, services: {}, window_specs: {}, doors: {})
      @session       = session
      @session_id    = session_id
      @context       = context
      @theme         = theme || Theme.synchronet
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

    def cols = @session.term_cols || 80
    def rows = @session.term_rows || 24

    def menubar=(menubar)
      @menubar = menubar
      menubar.theme = @theme if menubar
    end

    def statusbar=(statusbar)
      @statusbar = statusbar
      statusbar.theme = @theme if statusbar
    end

    def add(child)
      @root.add(child)
      child.theme = @theme
      child
    end

    # Overloaded: pass a Symbol/String to open a registered WindowSpec (with
    # optional extras forwarded into the callback ctx), or pass a Window
    # instance to push it directly onto the modal stack.
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
    def raise_window(window)
      return window if window == top_window || !@windows.include?(window)

      top_window.focused = false
      @windows.delete(window)
      @windows << window
      window.focused = true
      window
    end

    # The windows the caller can switch between, by their number. None
    # while a modal window (a dialog) is open: it keeps the front.
    def switchable_windows
      return [] if @windows.any?(&:modal)

      @windows.reject(&:modal).sort_by { |w| w.number || 10 }
    end

    # F6 / Shift-F6: the next or the previous window, by number.
    def cycle_windows(step = 1)
      list = switchable_windows
      return nil if list.size < 2

      index = list.index(top_window) || 0
      raise_window(list[(index + step) % list.size])
    end

    # Leaves the application through a declared door, from any handler: a
    # menu item, a key, a window button or a list's Enter. The event loop
    # stops after this event, and Builder#run opens the door. Returns :halt,
    # so a handler can also end with it.
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

    def close_window(window = nil)
      window ||= @windows.last
      return unless window
      @windows.delete(window)
      window.focused = false
      top_window&.focused = true
      window.on_close.call(window) if window.on_close.respond_to?(:call)
    end

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
    def run
      @running     = true
      idle_max     = BBS.config.idle_seconds
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

    # Periodic tick: notify on_tick callback and let each open window pull
    # any asynchronous updates by overriding BBS::Window#tick.
    def tick!
      @on_tick&.call(self)
      @windows.each { |w| w.tick(self) }
    end

    def stop! = (@running = false)

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
    class Builder
      attr_reader :init_block, :theme, :menubar_block, :statusbar_hints,
                  :helper_module, :window_specs, :doors

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
        @door_block      = nil
      end

      # Declares a door: `program` is a BBS::FakeOS definition, a BBS::Flow
      # or a callable(session, context); `label` is its menu item.
      def door(name, program, label: nil)
        @doors[name.to_sym] = Door.new(name, program, label: label)
      end

      def services(hash = nil)
        return @services if hash.nil?
        @services = @services.merge(hash)
      end

      def window(name, type:, &block)
        spec = WindowSpec.new(name, type: type)
        block&.call(spec)
        @window_specs[name] = spec
        spec
      end

      # `theme BBS::Theme.dosnavigator`, `theme :dosnavigator`, or either
      # with a block that overrides roles. Without arguments it returns the
      # theme set so far.
      def theme(base = nil, &block)
        return @theme if base.nil? && block.nil?

        if block
          starting = case base
                     when Symbol then Theme.public_send(base)
                     when Theme  then base
                     when nil    then Theme.synchronet
                     else             base
                     end
          builder = ThemeBuilder.new(starting)
          builder.instance_eval(&block)
          @theme = builder.build
        else
          @theme = base.is_a?(Symbol) ? Theme.public_send(base) : base
        end
      end

      def init(&block) = (@init_block = block)

      # Runs on the application (like a menu item) once a second while the
      # caller is idle: a clock, a counter on the statusbar, a poll.
      def on_tick(&block) = (@tick_block = block)

      # Runs with the door and the context just before Builder#run hands the
      # line to a door: who is where, a log line.
      def on_door(&block) = (@door_block = block)
      def helpers(&block) = @helper_module.module_eval(&block)
      def menubar(&block) = (@menubar_block = block)

      def status_hint(key, label, hidden: false, &on_activate)
        @statusbar_hints << [key, label, on_activate, hidden]
      end

      def body(&block)
        @body_block = block
      end

      def build(session:, session_id:, context: {})
        app = Application.new(
          session: session, session_id: session_id, context: context,
          theme: @theme || Theme.synchronet,
          helpers: @helper_module,
          services: @services,
          window_specs: @window_specs,
          doors: @doors,
          on_tick: @tick_block && ->(a) { a.instance_exec(&@tick_block) }
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
      # the caller leaves without one. The context lives through it all.
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

    # DSL inside `menubar do ... end`.
    class MenubarBuilder
      def initialize(menubar, app)
        @menubar = menubar
        @app     = app
      end

      def menu(label, &block)
        items_builder = ItemsBuilder.new(@app)
        items_builder.instance_eval(&block) if block
        @menubar.menus << Menubar::Menu.new(label: label, items: items_builder.items, x: nil)
      end
    end

    class ItemsBuilder
      attr_reader :items

      def initialize(app)
        @app   = app
        @items = []
      end

      # `enabled:` is true, false, or a lambda the application answers
      # each time the menu is drawn or used: `enabled: -> { current_doc }`.
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

    class BodyContext
      def initialize(app)
        @app = app
      end

      def add(widget) = @app.add(widget)
      def app         = @app
    end

    # DSL inside `theme do ... end`. Any unknown method call with one argument
    # is treated as a style override (e.g. `screen "\e[0m"`).
    class ThemeBuilder
      def initialize(base)
        @base      = base
        @overrides = {}
      end

      def inherit(theme)
        @base = theme.is_a?(Symbol) ? Theme.public_send(theme) : theme
      end

      def style(key, value)
        @overrides[key.to_sym] = value
      end

      def build
        @overrides.empty? ? @base : @base.merge(@overrides)
      end

      def respond_to_missing?(_name, _include_private = false) = true

      def method_missing(name, *args)
        return @overrides[name] = args.first if args.size == 1
        super
      end
    end
  end
end
