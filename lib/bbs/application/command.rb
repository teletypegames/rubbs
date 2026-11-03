# frozen_string_literal: true

module BBS
  class Application
    # Something the caller can do in an Application (Builder#command): its
    # menu label, its key, its word on the statusbar and the block it runs.
    Command = Struct.new(:name, :label, :key, :hint, :about, :action, keyword_init: true) do
      # Runs the action in +app+. Returns +:halt+ when the action did, else
      # +:handled+.
      def run(app)
        app.instance_exec(&action) == :halt ? :halt : :handled
      end

      # The word on the statusbar: +hint+, or the label without its
      # <tt>&</tt> and <tt>…</tt>.
      def hint_text = hint.is_a?(String) ? hint : Command.plain(label)
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

      # The built-in commands: +:menu+ (F10, only with a menubar) and
      # +:log_off+ (Alt-X), by name.
      def self.builtin(with_menubar: true)
        bye  = new(name: :log_off, label: '&Log off', key: 'Alt-X', hint: 'Bye', about: 'Hang up',
                   action: proc { log_off })
        bar  = new(name: :menu, label: 'Menu', key: 'F10', hint: 'Menu', action: proc { menubar&.open(0) })
        (with_menubar ? [bar, bye] : [bye]).to_h { |c| [c.name, c] }
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
