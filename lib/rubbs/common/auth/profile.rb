# frozen_string_literal: true

require_relative 'profile/drawing'

module Rubbs
  module Common
    module Auth
      # The caller's profile on either face, the same on every board: the
      # board's drawing in the middle, the title under it, who is on the line,
      # and a cursor menu (Rubbs::Common::Screens::Selector) of what they can do: log in or make
      # an account, change the password or log out. A board opens it from a
      # menu (Application: the built-in +:profile+ command; a
      # Rubbs::Petscii::Face: +open_profile+); how it looks comes from the board's
      # Rubbs::Common::Board::Preset (+profile:+, a Look), and without one it is plain.
      #
      #   Rubbs::Common::Auth::Profile.run(session)
      #
      #   look = Rubbs::Common::Auth::Profile::Look.new(modern: Rubbs::Common::Art.load('art/mini-modern.yml'),
      #                                       petscii: Rubbs::Common::Art.load('art/mini-c64.yml'))
      #   Rubbs::Common::Board::Preset.new(profile: look, …)
      class Profile
        include Drawing

        # How a profile looks:
        #
        # [modern]  a Rubbs::Common::Art over the title on a modern terminal, or +nil+
        # [petscii] a +petscii-upper+ Rubbs::Common::Art over it on a C64 (at most 13
        #           rows: the menu needs the rest), or +nil+
        # [title]   the line under the drawing
        # [note]    a line under the title for a guest (what an account is
        #           for), or +nil+
        # [words]   texts over WORDS (the items, the lines, the answers)
        # [colors]  colours of the roles (+title+, +text+, +dim+) on a modern
        #           terminal over COLORS, each an ANSI SGR
        # [c64]     colours of the same roles on a C64 over C64_COLORS, each a
        #           Rubbs::Petscii::Canvas colour (+:white+, +:yellow+ …)
        Look = Data.define(:modern, :petscii, :title, :note, :words, :colors, :c64) do
          # A look; every part has its default.
          def initialize(modern: nil, petscii: nil, title: 'PROFILE', note: nil, words: {}, colors: {}, c64: {}) = super
        end

        # The look of a board whose preset brings none.
        DEFAULT = Look.new
        # What the profile says, by key; <tt>%<name>s</tt> and
        # <tt>%<roles>s</tt> are filled in.
        WORDS = {
          log_in:     'Log in',
          register:   'New account',
          password:   'Change password',
          log_out:    'Log out',
          back:       'Back',
          guest:      'Not logged in',
          signed_in:  'Logged in as %<name>s',
          roles:      '%<roles>s',
          welcome:    'Welcome, %<name>s.',
          ready:      'Welcome, %<name>s. Your account is ready.',
          logged_out: 'You are logged out.',
          no_login:   'Nobody logs in on this board.',
          key:        'Press a key.',
          ok:         'Password changed.',
          differ:     'The two passwords differ.',
          invalid:    'A name is letters and digits, at most 20.',
          reserved:   'That name is kept for the board.',
          taken:      'That name has an account. Log in with it instead.',
          look_alike: 'That name looks too much like another account.',
          too_short:  "The password needs at least #{Directory::MIN_PASSWORD} characters.",
          mismatch:   'The two passwords differ.',
          **Login::WORDS
        }.freeze
        # The colours of the roles on a modern terminal (ANSI SGR).
        COLORS = { title: "\e[1;97m", text: Modern::Ansi::WHITE, dim: Modern::Ansi::GREY }.freeze
        # The colours of the roles on a C64 (Rubbs::Petscii::Canvas colours).
        C64_COLORS = { title: :white, text: :light_grey, dim: :grey }.freeze
        # The columns the menu takes.
        MENU_WIDTH = 22
        # The most rows of a C64 drawing.
        PETSCII_ROWS = 13

        # A place a board adds to the profile's menu (::extra): its +key+ (a
        # Symbol), the +label+, the +hotkey+ letter, +visible+ (a callable
        # given the session: whether the caller sees it now, or +nil+ for
        # always) and the +action+ (a callable given the session; it draws
        # its own screens, and the profile is shown again after it).
        Extra = Data.define(:key, :label, :hotkey, :visible, :action) do
          # Whether the caller on +session+ sees it.
          def visible_to?(session) = visible.nil? || visible.call(session) ? true : false
        end

        # Adds a place to the profile's menu of every caller of this process,
        # above Back: the board's own, which the library knows nothing of (a
        # sysop's console, the caller's settings). A place of the same +key+
        # is replaced. Returns the Extra.
        #
        # [key]    a Symbol
        # [label]  the words on the menu
        # [hotkey] the letter that takes it (the label's first by default)
        # [if]     a callable given the session: whether the caller sees it
        #
        #   Rubbs::Common::Auth::Profile.extra(:sysop, 'SysOp', if: ->(s) { s.identity.role?(:sysop) }) do |session|
        #     Console.run(session)
        #   end
        def self.extra(key, label, hotkey: nil, if: nil, &action)
          raise ArgumentError, 'an extra place needs a block' unless action

          place = Extra.new(
            key:     key.to_sym,
            label:   label.to_s,
            hotkey:  (hotkey || label.to_s[0]).to_s.downcase,
            visible: binding.local_variable_get(:if),
            action:  action
          )
          @extras = [*extras.reject { |e| e.key == place.key }, place]
          place
        end

        # The places boards added (::extra), in order.
        def self.extras = @extras ||= []

        # Forgets the places boards added (a test's teardown).
        def self.clear_extras = @extras = []

        # Runs the profile for the caller on +session+ until they go back;
        # with +start+ (+:log_in+ or +:register+) that is done first, as if
        # taken from the menu. Returns +nil+; raises Rubbs::Common::Line::Hangup when the line
        # drops.
        def self.run(session, setup: Rubbs.config.auth, look: Rubbs.config.preset.profile || DEFAULT, start: nil)
          new(session, setup, look).run(start: start)
        end

        # A profile for +session+ with +setup+ (a Rubbs::Common::Auth::Setup, or +nil+
        # on a board without a login) and +look+ (a Look).
        def initialize(session, setup, look)
          @session = session
          @setup   = setup
          @look    = look
          @words   = WORDS.merge(look.words)
          @colors  = COLORS.merge(look.colors)
          @c64     = C64_COLORS.merge(look.c64)
          @runner  = Call::FlowRunner.new(session, session.session_id, Call::Flow.new)
        end

        # Shows the profile and its menu, does what is taken, and shows it
        # again, until the caller goes back; +start+ (+:log_in+,
        # +:register+) is done first.
        def run(start: nil)
          return say_once(@words[:no_login]) unless @setup

          if start
            header
            act(start)
          end
          loop do
            header
            choice = menu.run
            return nil if choice.nil? || choice == :back

            header unless extras.any? { |e| e.key == choice }
            act(choice)
          end
        end

        private

        def identity = @session.identity

        def petscii? = @session.respond_to?(:petscii?) && @session.petscii?

        def items
          own = identity.signed_in? ? %i[password log_out] : %i[log_in register]
          own = own.map { |key| Screens::Selector.item(@words.fetch(key), key: @words.fetch(key)[0].downcase, value: key) }
          [*own, *extras.map { |e| Screens::Selector.item(e.label, key: e.hotkey, value: e.key) },
           Screens::Selector.item(@words[:back], key: @words[:back][0].downcase, value: :back)]
        end

        def extras = Profile.extras.select { |e| e.visible_to?(@session) }

        def menu
          labels = @words.values_at(:log_in, :register, :password, :log_out, :back) + extras.map(&:label)
          width  = [MENU_WIDTH, labels.map(&:length).max + 6].max
          cols   = petscii? ? Petscii::COLS - 1 : @session.term_cols.to_i
          Screens::Selector.new(@session, items, width: width, indent: [(cols - width) / 2, 0].max, back: :back)
        end

        def act(choice)
          extra = extras.find { |e| e.key == choice }
          return extra.action.call(@session) if extra

          case choice
          when :log_in   then log_in
          when :register then register
          when :password then password
          when :log_out  then log_out
          end
          pause
        end

        def log_in
          found = Login.new(@setup, @session, ask: method(:ask), tell: method(:tell)).run
          say(format(@words[:welcome], name: found.name)) if found
        end

        def register
          name = ask('name') or return
          password = ask('password', mask: '*') or return
          found = @setup.directory.register(name, password, ask('again', mask: '*').to_s)
          return tell(@words.fetch(found, @words[:unavailable])) unless found.is_a?(Identity)

          @session.identity = found
          say(format(@words[:ready], name: found.name))
        end

        def password
          old = ask('current password', mask: '*') or return
          fresh = ask('new password', mask: '*').to_s
          result = fresh == ask('again', mask: '*') ? change(old, fresh) : :differ
          result == :ok ? say(@words[:ok]) : tell(@words.fetch(result, @words[:unavailable]))
        end

        def change(old, fresh) = @setup.directory.change_password(identity.name, old, fresh, caller_key: @session.caller_key)

        def log_out
          Auth.event(:logout, name: identity.name)
          @session.identity = Identity.guest
          say(@words[:logged_out])
        end

        def ask(label, mask: nil)
          answer = @runner.ask("  #{label}: ", mask: mask)
          raise Line::Hangup if answer.nil?

          answer.empty? ? nil : answer
        end

        def tell(text) = @runner.line(text, style: :error)

        def say(text) = @runner.line(text, style: :success)

        def say_once(text)
          say(text)
          pause
          nil
        end

        def pause
          @runner.line(@words[:key], style: :muted)
          @session.readkey or raise Line::Hangup
        end
      end
    end
  end
end
