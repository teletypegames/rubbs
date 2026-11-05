# frozen_string_literal: true

require_relative 'widgets/widget'
require_relative 'window'
require_relative '../common/text/hotkey'

module Rubbs
  module Modern
    # A horizontal strip at the top of the screen with named drop-down menus.
    # Each menu has a label like <tt>&File</tt> (the letter after the
    # <tt>&</tt> is the hotkey, so Alt-F opens it) and a list of MenuItem
    # entries. F10 opens the first menu; the arrow keys, Enter, Esc, the item
    # hotkeys and the mouse work inside an open one.
    #
    # An Application fills it with its +menu+ DSL
    # (Rubbs::Modern::Application::MenubarBuilder#menu):
    #
    #   menubar do
    #     menu("&File") do
    #       item("&Open", shortcut: "F3") { |item| open_file }
    #       separator
    #       item("E&xit", shortcut: "Alt-X") { :halt }
    #     end
    #   end
    #
    # The bar itself never takes the keyboard focus (#focusable? is false);
    # the application passes events to #handle_event first.
    class Menubar < Widgets::Widget
      # The keys of an open menu and the method each one calls.
      KEYS = {
        left:   :previous_menu,
        right:  :next_menu,
        up:     :previous_item,
        down:   :next_item,
        escape: :close,
        f10:    :close,
        enter:  :activate
      }.freeze

      # The Array of Menu entries, in bar order.
      attr_reader :menus
      # A callable invoked with the MenuItem after any item is activated
      # (after its own block), or +nil+.
      attr_accessor :on_activate

      # Creates an empty menu bar; +kw+ (+id+, +bounds+, +theme+) go to
      # Widget.new.
      def initialize(**kw)
        super
        @menus       = []
        @open_index  = nil
        @item_index  = 0
        @on_activate = nil
      end

      # Returns whether a menu is dropped down.
      def open? = !@open_index.nil?

      # Returns the Menu that is dropped down, or +nil+.
      def opened_menu = @open_index && @menus[@open_index]

      # Returns the highlighted MenuItem of the open menu, or +nil+.
      def selected_item = opened_menu&.items&.[](@item_index)

      # Returns the hint of the highlighted item while a menu is open, or
      # +nil+ (no menu open, or the item has no hint).
      def selected_hint = open? ? selected_item&.hint : nil

      # Drops down the menu at +index+ (clamped to the existing menus) and
      # highlights its first enabled item. Does nothing when there are no
      # menus.
      def open(index)
        return if @menus.empty?

        @open_index = index.clamp(0, @menus.size - 1)
        @item_index = opened_menu.items.find_index(&:enabled?) || 0
      end

      # Closes the open menu, if any.
      def close
        @open_index = nil
        @item_index = 0
      end

      # Returns +false+: the bar never takes the keyboard focus.
      def focusable? = false

      # Draws the bar across its bounds into the Rubbs::Modern::FrameBuffer +frame+,
      # with the hotkey letters highlighted, and the open menu's drop-down
      # box with its shadow under it. Records each menu's column in Menu#x.
      def render(frame)
        frame.move(bounds.x, bounds.y)
        frame.write(' ' * bounds.width, sgr: style(:menubar))
        @menus.each_with_index.reduce(bounds.x + 1) { |x, (menu, i)| render_label(frame, menu, i, x) }
        dropdown&.render(frame, @item_index)
      end

      # Handles a keyboard or mouse event. Inside an open menu Left/Right
      # switch menus, Up/Down move to the previous/next enabled item, Enter
      # or an item's hotkey letter activates it, Esc or F10 closes the menu,
      # and a left click picks an item, switches menus or closes the menu
      # when outside it. Otherwise F10 or an Alt-hotkey opens a menu and a
      # left click on a label toggles it.
      #
      # Activating an item closes the menu, calls its +on_select+ block with
      # the item, then #on_activate. Returns +:halt+ when the block returned
      # +:halt+, +:handled+ when the bar used the event, +nil+ otherwise.
      def handle_event(event)
        return press(event) if left_press?(event)
        return (open? ? :handled : nil) if event.mouse?
        return navigate(event.key) if open?

        open_by_key(event)
      end

      private

      def left_press?(event) = event.mouse? && event.mouse.kind == :press && event.mouse.button == :left

      # The keys of an open menu.
      def navigate(key)
        return send(KEYS[key]).then { |r| r.is_a?(Symbol) ? r : :handled } if KEYS.key?(key)
        return :handled unless Common::Text.printable?(key)

        by_hotkey(key) || :handled
      end

      # F10 opens the first menu, an Alt-letter the menu of that hotkey.
      def open_by_key(event)
        index = event.key == :f10 ? 0 : event.alt_char && @menus.find_index { |m| m.hotkey == event.alt_char.downcase }
        return nil unless index

        self.open(index)
        :handled
      end

      # A left click: on the bar it toggles a menu; in the open dropdown it
      # picks an item; anywhere else it closes the menu.
      def press(event)
        return click_bar(event.x) if event.y == bounds.y
        return nil unless open?

        row = dropdown.item_at(event.x, event.y)
        return close.then { :handled } if row.nil?

        pick(row)
      end

      def click_bar(col)
        index = @menus.find_index { |m| m.at?(col) }
        index.nil? || @open_index == index ? close : self.open(index)
        :handled
      end

      # Activates item +row+ of the open menu when it can be chosen.
      def pick(row)
        return :handled unless row.between?(0, opened_menu.items.size - 1) && opened_menu.items[row].enabled?

        @item_index = row
        activate
      end

      def activate
        item = selected_item
        return :handled unless item&.enabled?

        close
        result = item.on_select&.call(item)
        @on_activate&.call(item)
        result == :halt ? :halt : :handled
      end

      def by_hotkey(char)
        index = opened_menu.items.find_index { |i| i.enabled? && i.hotkey == char.downcase }
        return nil unless index

        @item_index = index
        activate
      end

      def previous_menu = self.open((@open_index - 1) % @menus.size)

      def next_menu = self.open((@open_index + 1) % @menus.size)

      def previous_item = @item_index = step_item(-1)

      def next_item = @item_index = step_item(1)

      # The next enabled item in direction +dir+, round the end; the current
      # one when there is none.
      def step_item(dir)
        items = opened_menu.items
        (1..items.size).map { |n| (@item_index + (dir * n)) % items.size }.find { |i| items[i].enabled? } || @item_index
      end

      # The dropdown of the open menu, or +nil+.
      def dropdown
        menu = opened_menu
        menu && Dropdown.new(menu, bounds, ->(key) { style(key) })
      end

      # Draws the label of +menu+ (number +index+) at column +x+; returns the
      # column of the next one.
      def render_label(frame, menu, index, x)
        lit = @open_index == index
        menu.render(
          frame,
          x,
          bounds.y,
          style(lit ? :menubar_selected : :menubar),
          style(lit ? :menubar_sel_hot : :menubar_hotkey)
        )
      end
    end
  end
end

require_relative 'menu/items'
require_relative 'menu/dropdown'
