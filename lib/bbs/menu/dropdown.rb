# frozen_string_literal: true

module BBS
  class Menubar < Widget
    # The box an open menu drops down in, under its label on the bar,
    # shifted left when it would run off the right edge: its place, the
    # items drawn in it and which item a click lands on.
    class Dropdown
      # The columns around the longest label and shortcut: the borders and
      # the padding.
      CHROME = 6

      # Writes +label+ at the cursor of +frame+ in style +sgr+, its hotkey
      # letter (see BBS::Hotkey) in +hotkey_sgr+.
      def self.write_label(frame, label, sgr, hotkey_sgr)
        before, letter, after = Hotkey.split(label)
        return frame.write(Hotkey.plain(label), sgr: sgr) unless letter

        frame.write(before, sgr: sgr)
        frame.write(letter, sgr: hotkey_sgr)
        frame.write(after, sgr: sgr)
      end

      # The box of +menu+ under a bar with bounds +bar+ (a Widget::Rect);
      # +style+ is a callable returning the SGR of a theme role.
      def initialize(menu, bar, style)
        @menu   = menu
        @style  = style
        @width  = width_of(menu)
        @height = menu.items.size + 2
        @x      = [menu.x.to_i, bar.x + bar.width - @width].min.clamp(1..)
        @y      = bar.y + 1
      end

      # Draws the shadow, the box and the items into +frame+, item
      # +selected+ highlighted.
      def render(frame, selected)
        frame.shadow(x: @x, y: @y, width: @width, height: @height, sgr: @style.call(:window_shadow))
        frame.box(
          x:        @x,
          y:        @y,
          width:    @width,
          height:   @height,
          sgr:      @style.call(:menu_border),
          fill_sgr: @style.call(:menu_bg)
        )
        @menu.items.each_with_index { |item, i| render_item(frame, item, @y + 1 + i, i == selected) }
      end

      # The index of the item row at screen cell +x+, +y+ (-1 or the item
      # count on the borders), or +nil+ when the cell is outside the box.
      def item_at(x, y)
        return nil unless x >= @x && x < @x + @width && y >= @y && y < @y + @height

        y - @y - 1
      end

      private

      def width_of(menu)
        items = menu.items.reject(&:separator)
        (items.map { |i| i.display.length }.max || 0) + (items.map { |i| i.shortcut.to_s.length }.max || 0) + CHROME
      end

      def render_item(frame, item, row, selected)
        return frame.hline(x: @x + 1, y: row, length: @width - 2, sgr: @style.call(:menu_border)) if item.separator

        sgr = item_sgr(item, selected)
        frame.hline(x: @x + 1, y: row, length: @width - 2, char: ' ', sgr: sgr)
        frame.move(@x + 2, row)
        render_label(frame, item, sgr, selected)
        render_shortcut(frame, item.shortcut.to_s, row, sgr) if item.shortcut
      end

      def render_label(frame, item, sgr, selected)
        return frame.write(item.display, sgr: sgr) unless item.enabled?

        Dropdown.write_label(frame, item.label, sgr, selected ? sgr : @style.call(:menu_hotkey))
      end

      def item_sgr(item, selected)
        return @style.call(:menu_disabled) unless item.enabled?

        @style.call(selected ? :menu_selected : :menu_text)
      end

      def render_shortcut(frame, shortcut, row, sgr)
        frame.move(@x + @width - 1 - shortcut.length, row)
        frame.write(shortcut, sgr: sgr)
      end
    end
  end
end
