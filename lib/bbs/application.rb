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
  class Application
    attr_reader :session, :session_id, :context, :root, :menubar, :statusbar,
                :windows, :theme

    def self.define(&block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      builder
    end

    def initialize(session:, session_id:, context: {}, theme: nil, on_idle: nil,
                   on_tick: nil, helpers: nil)
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

    def open_window(window)
      window.theme = @theme
      @windows << window
      window.focused = true
      window
    end

    def close_window(window = nil)
      window ||= @windows.last
      return unless window
      @windows.delete(window)
      window.focused = false
      window.on_close&.call(window) if window.on_close
    end

    def top_window
      @windows.last
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
        break if key.nil?

        if key == :idle
          idle_elapsed += tick_seconds
          tick!
          if idle_max && idle_elapsed >= idle_max
            BBS::Dialogs.message(self, "Disconnected after #{idle_max.to_i}s idle.",
                                 title: ' Idle ')
            do_render
            sleep 0.5
            break
          end
          next
        end

        idle_elapsed = 0.0
        event  = build_event(key)
        result = dispatch(event)
        break if result == :halt
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
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

      # Modal windows: top window gets first shot at events
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
                  :helper_module

      def initialize
        @init_block      = nil
        @theme           = nil
        @menubar_block   = nil
        @statusbar_hints = []
        @body_block      = nil
        @helper_module   = Module.new
      end

      def theme(base = nil, &block)
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
          @theme = base
        end
      end

      def init(&block) = (@init_block = block)
      def helpers(&block) = @helper_module.module_eval(&block)
      def menubar(&block) = (@menubar_block = block)

      def status_hint(key, label, &on_activate)
        @statusbar_hints << [key, label, on_activate]
      end

      def body(&block)
        @body_block = block
      end

      def build(session:, session_id:, context: {})
        app = Application.new(
          session: session, session_id: session_id, context: context,
          theme: @theme || Theme.synchronet,
          helpers: @helper_module
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
          @statusbar_hints.each do |k, l, blk|
            wrapped = blk ? ->{ app.instance_exec(&blk) } : ->{ nil }
            sb.add_hint(k, l, &wrapped)
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

      def item(label, shortcut: nil, enabled: true, &block)
        @items << Menubar::MenuItem.new(
          label: label, shortcut: shortcut, enabled: enabled, separator: false,
          on_select: block ? ->(item) { @app.instance_exec(item, &block) } : nil
        )
      end

      def separator
        @items << Menubar::MenuItem.new(label: '', shortcut: nil, enabled: false,
                                        separator: true, on_select: nil)
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
