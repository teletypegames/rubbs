# frozen_string_literal: true

require_relative 'command'
require_relative 'desktop_builder'
require_relative 'bars'

module BBS
  class Application
    # The DSL of Application.define. Its methods record the application's
    # parts; #build makes an Application from them for one session, and #run
    # runs it with its doors.
    #
    #   BBS::Application.define do
    #     theme :synchronet
    #     command :search, 'Search…', key: 'F2' do search end
    #     menu 'Wiki', :search, :separator, :log_off
    #     help about: ABOUT
    #     status { "#{lang}.wikipedia.org" }
    #     desktop { art LOGO, top: 2; on_show { search } }
    #     window(:results, :master_detail) { items { results } }
    #   end
    class Builder
      include Bars

      # The methods a BBS::Part may record and replay on a Builder.
      DSL = %i[door doors services window theme init on_tick on_idle on_door helpers command menu help status
               desktop parts].freeze

      # The window specs by name and the commands by name.
      attr_reader :window_specs, :commands

      # Creates an empty Builder; Application.define makes one.
      def initialize
        @helper_module = Module.new
        @services      = nil
        @window_specs  = {}
        @doors         = {}
        @commands      = {}
        @menus         = []
        @help          = nil
        @status        = nil
        @clock         = true
        @desktop       = nil
      end

      # Declares a door: +program+ is a BBS::FakeOS definition, a BBS::Flow
      # or a callable <tt>call(session, context)</tt>; +label+ is its menu
      # item (default: the upcased name), +hint+ a line about it for the
      # statusbar while its menu item is highlighted. Returns the BBS::Door.
      # Raises ArgumentError when +program+ is none of these.
      #
      # A BBS::Door made elsewhere (the domain's list of doors) is declared
      # as it is: <tt>door(a_door)</tt>. The block form names the doors made
      # for each call: <tt>doors { board.doors }</tt> (see #doors).
      def door(name, program = nil, label: nil, hint: nil)
        return @doors[name.name] = name if name.is_a?(Door)

        @doors[name.to_sym] = Door.new(name, program, label: label, hint: hint)
      end

      # Declares doors given by the block (evaluated in the application when
      # it is built, so the board's domain is at hand), BBS::Door objects.
      def doors(&block) = (@doors_block = block)

      # Merges +hash+ into the services of the application (readers of the
      # same names on it, and in its windows). Without any call the
      # application gets the services of the board's domain object
      # (BBS::Config#board). Without an argument returns the services so far.
      def services(hash = nil)
        return @services || {} if hash.nil?

        @services = (@services || {}).merge(hash)
      end

      # Declares the window +name+ of +type+ (see BBS::WindowSpec), opened
      # with <tt>open(name, **extras)</tt>; the block is evaluated in the
      # spec. Returns the spec.
      def window(name, type, &)
        @window_specs[name.to_sym] = WindowSpec.new(name.to_sym, type, &)
      end

      # Sets the application's theme: <tt>theme :dosnavigator</tt> or a
      # BBS::Theme, either with a block that overrides roles (evaluated in a
      # ThemeBuilder; a block alone starts from <tt>BBS.config.theme</tt>,
      # or BBS::Theme.synchronet). Without arguments returns the theme set
      # so far (+nil+ before any). Raises ArgumentError for a name that is
      # not one of BBS::Theme::PRESETS, NoMethodError for a role the block
      # sets that no preset knows.
      def theme(base = nil, &block)
        return @theme if base.nil? && block.nil?

        starting = base.nil? ? BBS.config.theme || Theme.synchronet : Theme.fetch(base)
        @theme   = block ? ThemeBuilder.new(starting).tap { |b| b.instance_eval(&block) }.build : starting
      end

      # Sets the block run in the application after it is built, before the
      # desktop: per-call state (<tt>context[:lang] ||= 'en'</tt>).
      def init(&block) = (@init_block = block)

      # Sets the block run in the application once a second while the
      # caller is idle, after the statusbar's #status is refreshed.
      def on_tick(&block) = (@tick_block = block)

      # Sets the block run in the application when the caller reaches the
      # idle limit; calling +keep_on+ in it keeps them on.
      def on_idle(&block) = (@idle_block = block)

      # Sets the block called with the BBS::Door and the context just before
      # #run hands the line to a door.
      def on_door(&block) = (@door_block = block)

      # Evaluates the block in the module of the application's helpers:
      # methods defined there are methods of the application (and of its
      # windows' blocks).
      def helpers(&) = @helper_module.module_eval(&)

      # Declares the command +name+: what the caller can do, said once. The
      # block runs in the application. +label+ is its menu item (an
      # <tt>&</tt> marks the hotkey; without one the menu picks a letter),
      # +key+ its key anywhere (<tt>'F2'</tt>, <tt>'Alt-R'</tt>), +hint+ its
      # word on the statusbar (default: the label without <tt>&</tt> and
      # <tt>…</tt>; +false+ binds the key without showing it), +about+ the
      # statusbar line while its menu item is highlighted, +role+ the
      # BBS::Auth role it is for (its menu item is greyed out, and its key
      # says so, for a caller without it), +if+ a block evaluated in the
      # application that says whether it can run now (greyed out
      # otherwise). The commands +:menu+ (F10) and
      # +:log_off+ (Alt-X) are built in, and +:log_in+ and +:log_out+ for a
      # board with a login (BBS.board's +auth+); declaring one of them
      # replaces it.
      #
      #   command :search, 'Search…', key: 'F2' do search end
      def command(name, label, key: nil, hint: nil, about: nil, role: nil, if: nil, &action)
        @commands[name.to_sym] = Command.new(
          name:      name.to_sym,
          label:     label,
          key:       key,
          hint:      hint,
          about:     about,
          action:    action,
          role:      role,
          available: binding.local_variable_get(:if)
        )
      end

      # Declares a menu of the menubar. Its +entries+ are command names,
      # +:separator+ and +:doors+ (one item per door); the block, evaluated in
      # an ItemsBuilder, adds more (+command+, +item+, +separator+, +doors+).
      #
      #   menu 'Wiki', :search, :random, :separator, :log_off
      def menu(label, *entries, &block)
        @menus << [label, entries, block]
      end

      # Declares the Help menu: <tt>About</tt> showing +about+, one item per
      # other page (<tt>reading: READING</tt> becomes "Reading"), and
      # <tt>Keys</tt>, written from the commands and rubbs' own keys, with
      # +keys+ (lines of the board's own) added.
      #
      # +pages+ may also be given as a Hash with String titles (<tt>help({
      # 'Jargon File' => JARGON }, about: ABOUT)</tt>). +about+ may be a block
      # (evaluated in the application when chosen). The block, evaluated in
      # an ItemsBuilder, adds the board's own items before the pages.
      def help(titled = {}, about: nil, keys: [], **pages, &items)
        @help = { about: about, keys: Array(keys), pages: titled.merge(pages), items: items }
      end

      # Sets the block whose text is the right end of the statusbar,
      # refreshed every second; the clock follows it (+clock: :before+ puts it
      # first, +false+ leaves it out).
      def status(clock: true, &block)
        @clock  = clock
        @status = block
      end

      # Declares the desktop under the windows, evaluated in a
      # DesktopBuilder: art, lines, a widget, buttons, and what opens first.
      def desktop(&) = (@desktop = DesktopBuilder.new(&))

      # Replays the declarations of each BBS::Part in +parts+ here.
      def parts(*parts)
        parts.flatten.each { |part| part.install(self) }
      end

      # Makes an Application for +session+ from the declarations: theme,
      # helpers, services, windows, doors, menubar and statusbar, then runs
      # #init and puts up the #desktop. Returns the Application, not yet
      # running.
      def build(session:, session_id:, context: {})
        app = new_application(session, session_id, context)
        add_doors(app)
        app.menubar   = build_menubar(app) unless @menus.empty? && @help.nil?
        app.statusbar = build_statusbar(app)
        app.instance_exec(&@init_block) if @init_block
        @desktop&.install(app)
        app.refresh_status
        @desktop&.show(app)
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

      # The commands of an application, the built-in ones after the
      # board's: what the statusbar shows and the Keys page lists.
      def all_commands
        builtin = Command.builtin(with_menubar: !@menus.empty? || !@help.nil?)
        @commands.reject { |name, _| builtin.key?(name) }.merge(builtin.to_h { |name, c| [name, @commands[name] || c] })
      end

      private

      def new_application(session, session_id, context)
        Application.new(
          session:      session,
          session_id:   session_id,
          context:      context,
          theme:        @theme,
          helpers:      @helper_module,
          services:     app_services,
          window_specs: @window_specs,
          doors:        @doors.dup,
          on_tick:      on_app(@tick_block),
          on_idle:      on_app(@idle_block),
          status:       @status,
          clock:        @clock
        )
      end

      def add_doors(app)
        Array(@doors_block && app.instance_exec(&@doors_block)).each { |door| app.doors[door.name] = door }
      end

      def app_services
        return @services.dup.freeze if @services

        board = BBS.config.board
        (board.respond_to?(:services) ? board.services : {}).dup.freeze
      end

      def on_app(block) = block && ->(app) { app.instance_exec(&block) }
    end

    # The items of one menu (Builder#menu), evaluated with +instance_eval+.
    class ItemsBuilder
      # The MenuItems added so far.
      attr_reader :items

      # A builder for a menu of +app+, whose entries name +commands+ (a
      # Hash of Command by name).
      def initialize(app, commands = {})
        @app      = app
        @commands = commands
        @items    = []
        @letters  = []
      end

      # Adds what +entry+ names: a command, +:separator+ or +:doors+.
      # Raises ArgumentError for an unknown name.
      def entry(entry)
        case entry
        when :separator then separator
        when :doors     then doors
        else command(entry)
        end
      end

      # Adds the item of the command +name+: its label, its key as the
      # shortcut, its +about+ as the hint. Raises ArgumentError for an
      # unknown command.
      def command(name)
        command = @commands[name.to_sym] or raise ArgumentError, "Unknown command: #{name.inspect}"
        add(
          command.label,
          command.key,
          command.about,
          ->(_item) { command.run(@app) },
          enabled: -> { command.available?(@app) }
        )
      end

      # Adds an item that runs the block in the application. +enabled+ may
      # be a block evaluated in the application each time the menu opens.
      def item(label, shortcut: nil, enabled: true, hint: nil, &block)
        if enabled.is_a?(Proc)
          check   = enabled
          enabled = -> { @app.instance_exec(&check) }
        end
        add(label, shortcut, hint, block ? ->(item) { @app.instance_exec(item, &block) } : nil, enabled: enabled)
      end

      # Adds a separator line.
      def separator
        @items << Menubar::MenuItem.new(label: '', shortcut: nil, enabled: false, separator: true, on_select: nil)
      end

      # Adds one item per door of the application.
      def doors
        @app.doors.each_value do |door|
          item(door.label, hint: door.hint) { open_door(door.name) }
        end
      end

      private

      def add(label, shortcut, hint, on_select, enabled: true)
        label = Command.hotkeyed(label, @letters)
        @letters << Command.hotkey(label)
        @items << Menubar::MenuItem.new(
          label:     label,
          shortcut:  shortcut,
          enabled:   enabled,
          separator: false,
          hint:      hint,
          on_select: on_select
        )
      end
    end

    # Overrides the roles of a theme (Builder#theme with a block): each
    # one-argument call naming a role (+accent+, +window_title+, …) sets it.
    class ThemeBuilder
      # A builder starting from the BBS::Theme +base+.
      def initialize(base)
        @base      = base
        @overrides = {}
      end

      # Starts from +theme+ (a BBS::Theme or a preset name) instead.
      def inherit(theme)
        @base = Theme.fetch(theme)
      end

      # Sets the role +key+ to the SGR String +value+.
      def style(key, value)
        @overrides[key.to_sym] = value
      end

      # The theme: the base with the overrides.
      def build
        @overrides.empty? ? @base : @base.merge(@overrides)
      end

      # Whether +name+ is a role of the themes.
      def respond_to_missing?(name, include_private = false) = Theme.roles.include?(name) || super

      # Sets the role +name+ to the one argument.
      def method_missing(name, *args)
        return @overrides[name] = args.first if args.size == 1 && Theme.roles.include?(name)

        super
      end
    end
  end
end
