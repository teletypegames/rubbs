# frozen_string_literal: true

module BBS
  class Menubar < Widget
    # One menu on the bar: +label+ with an optional <tt>&</tt> before the
    # hotkey letter, +items+ an Array of MenuItem, +x+ the column it was last
    # drawn at (+nil+ before the first render).
    Menu = Struct.new(:label, :items, :x, keyword_init: true) do
      # The lower-case hotkey letter, or +nil+.
      def hotkey = Hotkey.letter(label)

      # The label without the <tt>&</tt>.
      def display = Hotkey.plain(label)

      # Draws the label padded by a space each side at column +x+, row +y+
      # of +frame+ in style +sgr+, the hotkey in +hotkey_sgr+, and
      # remembers +x+. Returns the column of the next label.
      def render(frame, x, y, sgr, hotkey_sgr)
        self.x = x
        frame.move(x, y)
        frame.write(' ', sgr: sgr)
        Dropdown.write_label(frame, label, sgr, hotkey_sgr)
        frame.write(' ', sgr: sgr)
        x + display.length + 3
      end

      # Whether column +col+ of the bar is on this menu's label.
      def at?(col) = x && col >= x && col < x + display.length + 2
    end

    # One entry of a menu, built by the Application menu DSL: +label+ (with
    # an optional <tt>&</tt> before the hotkey letter), +shortcut+ (text
    # shown at the right edge, for display only), +enabled+ (+true+,
    # +false+ or a callable asked each time), +on_select+ (the block called
    # with the item when it is chosen), +separator+ (a dividing line rather
    # than an entry) and +hint+ (a line about the entry that the
    # Application shows on the statusbar while the entry is highlighted, or
    # +nil+).
    MenuItem = Struct.new(:label, :shortcut, :enabled, :on_select, :separator, :hint,
                          keyword_init: true) do
      # The lower-case hotkey letter, or +nil+ (always for a separator).
      def hotkey = separator ? nil : Hotkey.letter(label)

      # The text shown.
      def display = separator ? '─' : Hotkey.plain(label)

      # Returns whether the item can be chosen: never for a separator; a
      # callable +enabled+ is asked every time; otherwise only +false+
      # disables.
      def enabled?
        return false if separator
        return enabled.call ? true : false if enabled.respond_to?(:call)

        enabled != false
      end
    end
  end
end
