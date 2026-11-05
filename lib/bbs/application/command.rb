# frozen_string_literal: true

module BBS
  class Application
    # Something the caller can do in an Application (Builder#command): its
    # menu label, its key, its word on the statusbar, the block it runs, the
    # +role+ it is for (BBS::Auth; +nil+: everyone) and +available+, a block
    # evaluated in the application that says whether it can run now.
    Command = Struct.new(:name, :label, :key, :hint, :about, :action, :role, :available, keyword_init: true) do
      # Runs the action in +app+. Returns +:halt+ when the action did, else
      # +:handled+. A command for a role the caller lacks says so instead.
      # Each run but the menubar's (+:menu+) writes a +use+ line (Log.use).
      def run(app)
        return refuse(app) unless available?(app)

        Log.use(name, kind: :command, face: :modern) unless name == :menu
        app.instance_exec(&action) == :halt ? :halt : :handled
      end

      # Whether the caller in +app+ may run it now: they have its +role+ and
      # its +available+ block agrees. Its menu item is greyed out otherwise.
      def available?(app)
        (role.nil? || app.role?(role)) && (available.nil? || app.instance_exec(&available) ? true : false)
      end

      # The word on the statusbar: +hint+, or the label without its
      # <tt>&</tt> and <tt>…</tt>.
      def hint_text = hint.is_a?(String) ? hint : Command.plain(label)

      private

      def refuse(app)
        app.message("This is for the #{role} role.", title: 'Not for you') if role && !app.role?(role)
        :handled
      end
    end

    # The built-in commands and the Keys page of the Help menu.
    class Command
      # The keys of every Application, for the Keys page after the
      # commands.
      GENERIC_KEYS = [
        'Alt+letter   open a menu',
        'Tab          next field or button (Shift-Tab: back)',
        'Enter        open, choose',
        'Esc          close the window',
        'F5           full screen and back (also Alt-Enter)',
        'F6           next window (Shift-F6: previous, Alt-1…9: by number)',
        'Ctrl-F5      move and size the window with the arrows'
      ].freeze

      # The width of the key column on the Keys page.
      KEY_WIDTH = 13

      # The built-in commands: +:menu+ (F10, only with a menubar),
      # +:log_off+ (Alt-X), and +:profile+, +:log_in+ and +:log_out+
      # (BBS::Auth; greyed out on a board without a login), by name.
      def self.builtin(with_menubar: true)
        bye = new(
          name:   :log_off,
          label:  '&Log off',
          key:    'Alt-X',
          hint:   'Bye',
          about:  'Hang up',
          action: proc { log_off }
        )
        bar = new(name: :menu, label: 'Menu', key: 'F10', hint: 'Menu', action: proc { menubar&.open(0) })
        commands = (with_menubar ? [bar, bye] : [bye])
        commands += auth
        commands.to_h { |c| [c.name, c] }
      end

      # The +:profile+, +:log_in+ and +:log_out+ commands, each available
      # when it fits.
      def self.auth
        [
          new(
            name:      :profile,
            label:     'Profile…',
            about:     'Your account: log in, a new account, the password',
            action:    proc { open_profile },
            available: proc { BBS.config.auth }
          ),
          new(
            name:      :log_in,
            label:     'Log in…',
            about:     'Log in to your account',
            action:    proc { log_in },
            available: proc { BBS.config.auth && !signed_in? }
          ),
          new(
            name:      :log_out,
            label:     'Log out',
            about:     'Log out, staying on the line',
            action:    proc { log_out_now },
            available: proc { signed_in? }
          )
        ]
      end

      # +label+ without its <tt>&</tt> and a trailing <tt>…</tt>.
      def self.plain(label) = label.to_s.delete('&').delete_suffix('…').strip

      # The hotkey letter of +label+ (after its <tt>&</tt>), downcased, or
      # +nil+.
      def self.hotkey(label) = label[/&(.)/, 1]&.downcase

      # +label+ with an <tt>&</tt>: as given when it has one, else before
      # its first letter not in +taken+ (lower-case letters), else none.
      def self.hotkeyed(label, taken)
        return label if label.include?('&')

        index = label.each_char.with_index.find { |c, _| c.match?(/[[:alnum:]]/) && !taken.include?(c.downcase) }&.last
        index ? label.dup.insert(index, '&') : label
      end

      # The lines of the Keys page: each command with a key, the board's
      # +extra+ lines, then GENERIC_KEYS.
      def self.keys_page(commands, extra = [])
        own = commands.select(&:key).map { |c| "#{c.key.ljust(KEY_WIDTH)}#{plain(c.label)}" }
        [*own, *extra, '', *GENERIC_KEYS]
      end
    end
  end
end
