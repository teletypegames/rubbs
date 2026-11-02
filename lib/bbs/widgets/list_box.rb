# frozen_string_literal: true

module BBS
  module Widgets
    # A scrolling list of items with one selected.
    class ListBox < Widget
      include Drawing

      # [items]       the Array of items shown
      # [selected]    index of the selected item
      # [scroll]      index of the item on the top row
      # [on_select]   callable invoked as <tt>call(item, listbox)</tt> when
      #               the selection moves to another item
      # [on_activate] callable invoked as <tt>call(item, listbox)</tt> on
      #               Enter; its result is returned from #handle_event
      # [label]       callable turning an item into its display text;
      #               +nil+ uses the item's +to_s+
      attr_accessor :items, :selected, :scroll, :on_select, :on_activate, :label

      # Creates a list of +items+ with the first one selected.
      def initialize(items: [], on_select: nil, on_activate: nil, label: nil, **kw)
        super(**kw)
        @items       = items
        @selected    = 0
        @scroll      = 0
        @on_select   = on_select
        @on_activate = on_activate
        @label       = label
      end

      # True: a list takes the focus.
      def focusable? = true
      # The selected item, or +nil+ when the list is empty.
      def selected_item = @items[@selected]

      # Draws the visible items into the bounds of +frame+, the selected one
      # highlighted (more strongly when the list has the focus).
      def render(frame)
        return if no_room?

        bounds.height.times { |r| draw_row(frame, r) }
      end

      # Moves the selection with Up, Down, Page Up, Page Down, Home and End
      # (calling +on_select+ when it changes), calls +on_activate+ on Enter,
      # selects the clicked item on a left click and scrolls the selection by
      # three on the mouse wheel. Returns :handled (or +on_activate+'s result
      # on Enter), and +nil+ for other events or when disabled.
      def handle_event(event)
        return nil unless enabled
        return key(event.key) if event.key?
        return click(event.y - bounds.y) if Widgets.click_in?(event, bounds)

        rows = Widgets.wheel(event, bounds)
        rows && select(@selected + rows)
      end

      private

      def key(name)
        return @on_activate&.call(selected_item, self) || :handled if name == :enter

        target = target_of(name)
        target && select(target)
      end

      # The index key +name+ moves the selection to, or +nil+.
      def target_of(name)
        case name
        when :up        then @selected - 1
        when :down      then @selected + 1
        when :page_up   then @selected - bounds.height
        when :page_down then @selected + bounds.height
        when :home      then 0
        when :end       then @items.size - 1
        end
      end

      # Selects the item on the clicked +row+ (no scrolling).
      def click(row)
        index = @scroll + row
        if index < @items.size
          before = @selected
          @selected = index
          @on_select&.call(selected_item, self) if before != index
        end
        :handled
      end

      # Selects item +index+ (kept in the list), scrolls to it and calls
      # +on_select+ when the selection changed. Returns :handled.
      def select(index)
        return :handled if @items.empty?

        before    = @selected
        @selected = index.clamp(0, @items.size - 1)
        adjust_scroll
        @on_select&.call(selected_item, self) if before != @selected
        :handled
      end

      def draw_row(frame, row)
        index = @scroll + row
        blank(frame, row, style(:listbox))
        item = @items[index] or return

        sgr = row_sgr(index)
        blank(frame, row, sgr) if index == @selected
        put(frame, 0, row, (@label ? @label.call(item) : item.to_s)[0, bounds.width], sgr)
      end

      def row_sgr(index)
        return style(:listbox) unless index == @selected

        focused ? style(:listbox_focused) : style(:listbox_selected)
      end

      def adjust_scroll
        @scroll = @selected if @selected < @scroll
        @scroll = @selected - bounds.height + 1 if @selected >= @scroll + bounds.height
        @scroll = [@scroll, 0].max
      end
    end
  end
end
