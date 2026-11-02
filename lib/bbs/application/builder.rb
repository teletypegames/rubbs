# frozen_string_literal: true

module BBS
  class Application
    # The DSL of Application.define. Its methods record the application's
    # parts; #build makes an Application from them for one session, and #run
    # runs it with its doors.
    class Builder
      # Creates an empty Builder; Application.define makes one.
      def initialize
        @statusbar_hints = []
        @helper_module   = Module.new
        @services        = {}
        @window_specs    = {}
        @doors           = {}
      end

      # Declares a door: +program+ is a BBS::FakeOS definition, a BBS::Flow
      # or a callable <tt>call(session, context)</tt>; +label+ is its menu
      # item (default: the upcased name), +hint+ a line about it for the
      # statusbar while its menu item is highlighted. Returns the BBS::Door. Raises
      # ArgumentError when +program+ is none of these.
      def door(name, program, label: nil, hint: nil)
        @doors[name.to_sym] = Door.new(name, program, label: label, hint: hint)
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
      # arguments it returns the theme set so far (+nil+ before any). With no
      # #theme call at all the application gets <tt>BBS.config.theme</tt>
      # (see Application.new). Raises ArgumentError for a name that is not
      # one of BBS::Theme::PRESETS, NoMethodError for a role the block sets
      # that no preset knows.
      def theme(base = nil, &block)
        return @theme if base.nil? && block.nil?

        starting = base.nil? ? BBS.config.theme || Theme.synchronet : Theme.fetch(base)
        @theme   = block ? ThemeBuilder.new(starting).tap { |b| b.instance_eval(&block) }.build : starting
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
      def helpers(&) = @helper_module.module_eval(&)
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
        app = new_application(session, session_id, context)
        app.menubar = build_menubar(app) if @menubar_block
        app.statusbar = build_statusbar(app) unless @statusbar_hints.empty?
        app.instance_exec(&@init_block) if @init_block
        BodyContext.new(app).instance_exec(&@body_block) if @body_block
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

      private

      def new_application(session, session_id, context)
        Application.new(session: session, session_id: session_id, context: context, theme: @theme,
                        helpers: @helper_module, services: @services.dup.freeze, window_specs: @window_specs,
                        doors: @doors, on_tick: on_app(@tick_block), on_idle: on_app(@idle_block))
      end

      # +block+ run on the application it is called with, or +nil+.
      def on_app(block) = block && ->(app) { app.instance_exec(&block) }

      def build_menubar(app)
        menubar = Menubar.new
        menubar.theme = app.theme
        MenubarBuilder.new(menubar, app).instance_eval(&@menubar_block)
        menubar
      end

      def build_statusbar(app)
        statusbar = Statusbar.new
        statusbar.theme = app.theme
        @statusbar_hints.each do |key, label, block, hidden|
          statusbar.add_hint(key, label, hidden: hidden) { block && app.instance_exec(&block) }
        end
        statusbar
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
      # beside it and an optional +hint+, a line the statusbar shows while
      # the item is highlighted. The block runs on the application, with the
      # item as its argument, when the item is chosen.
      #
      # +enabled+ is true, false, or a lambda the application answers each
      # time the menu is drawn or used:
      #
      #   item('&Save', enabled: -> { current_doc }) { save }
      def item(label, shortcut: nil, enabled: true, hint: nil, &block)
        if enabled.is_a?(Proc)
          check   = enabled
          enabled = -> { @app.instance_exec(&check) }
        end
        @items << Menubar::MenuItem.new(
          label: label, shortcut: shortcut, enabled: enabled, separator: false, hint: hint,
          on_select: block ? ->(item) { @app.instance_exec(item, &block) } : nil
        )
      end

      # Adds a separator line between items.
      def separator
        @items << Menubar::MenuItem.new(label: '', shortcut: nil, enabled: false,
                                        separator: true, on_select: nil)
      end

      # One item per declared door, in declaration order, each with the
      # door's hint.
      def doors
        @app.doors.each_value do |door|
          item(door.label, hint: door.hint) { open_door(door.name) }
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
      attr_reader :app
    end

    # DSL inside <tt>theme do ... end</tt>. A call named after a style role
    # (one of BBS::Theme.roles) with one argument is a style override (e.g.
    # <tt>screen "\e[0m"</tt>).
    class ThemeBuilder
      # Starts from +base+, a BBS::Theme, with no overrides.
      def initialize(base)
        @base      = base
        @overrides = {}
      end

      # Replaces the base theme with +theme+, a BBS::Theme or the name of one
      # of its presets (a Symbol such as +:dosnavigator+). Raises
      # ArgumentError for an unknown name.
      def inherit(theme)
        @base = Theme.fetch(theme)
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

      # True for the style roles (BBS::Theme.roles), the names
      # #method_missing takes.
      def respond_to_missing?(name, include_private = false) = Theme.roles.include?(name) || super

      # Treats <tt>role value</tt> as <tt>style(role, value)</tt> for a style
      # role of BBS::Theme.roles. Any other name, or another number of
      # arguments, raises NoMethodError.
      def method_missing(name, *args)
        return @overrides[name] = args.first if args.size == 1 && Theme.roles.include?(name)

        super
      end
    end
  end
end
