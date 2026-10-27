# frozen_string_literal: true

require_relative 'widget'
require_relative 'window'

module BBS
  # Menubar — a horizontal strip at the top of the screen with named
  # menus. Each menu has a label like "&File" (Alt-F opens it) and a list of
  # MenuItem objects.
  class Menubar < Widget
    Menu = Struct.new(:label, :items, :x, keyword_init: true) do
      def hotkey
        idx = label.index('&')
        idx && idx + 1 < label.length ? label[idx + 1].downcase : nil
      end

      def display = label.sub('&', '')
    end

    MenuItem = Struct.new(:label, :shortcut, :enabled, :on_select, :separator,
                          keyword_init: true) do
      def hotkey
        return nil if separator
        idx = label.index('&')
        idx && idx + 1 < label.length ? label[idx + 1].downcase : nil
      end

      def display = separator ? '─' : label.sub('&', '')

      # A lambda is asked every time; otherwise only false disables.
      def enabled?
        return false if separator
        return enabled.call ? true : false if enabled.respond_to?(:call)

        enabled != false
      end
    end

    attr_reader :menus
    attr_accessor :on_activate

    def initialize(**kw)
      super
      @menus       = []
      @open_index  = nil
      @item_index  = 0
      @on_activate = nil
    end

    def add_menu(label, &block)
      builder = MenuBuilder.new
      builder.instance_eval(&block) if block
      @menus << Menu.new(label: label, items: builder.items, x: nil)
      self
    end

    def open?           = !@open_index.nil?
    def opened_menu     = @open_index ? @menus[@open_index] : nil
    def open_index      = @open_index
    def selected_item   = opened_menu&.items&.[](@item_index)

    def open(index)
      return if @menus.empty?

      idx = index.clamp(0, @menus.size - 1)
      @open_index = idx
      @item_index = first_selectable_index(@menus[idx].items) || 0
    end

    def close
      @open_index = nil
      @item_index = 0
    end

    def focusable? = false

    def render(frame)
      sgr     = style(:menubar)
      sel     = style(:menubar_selected)
      hotkey  = style(:menubar_hotkey)
      sel_hot = style(:menubar_sel_hot)

      frame.move(bounds.x, bounds.y)
      frame.write(' ' * bounds.width, sgr: sgr)

      cx = bounds.x + 1
      @menus.each_with_index do |menu, i|
        menu.x = cx
        is_open = (@open_index == i)
        slabel  = is_open ? sel    : sgr
        shotkey = is_open ? sel_hot : hotkey
        frame.move(cx, bounds.y)
        frame.write(' ', sgr: slabel)
        render_hotkey_label(frame, menu.label, cx + 1, bounds.y, slabel, shotkey)
        frame.move(cx + 1 + menu.display.length, bounds.y)
        frame.write(' ', sgr: slabel)
        cx += menu.display.length + 3
      end

      render_dropdown(frame) if open?
    end

    def handle_event(event)
      return navigate(event) if open?
      return open_via_keyboard(event) if event.key?
      if event.mouse? && event.mouse.kind == :press && event.mouse.button == :left
        return handle_mouse_press(event)
      end
      nil
    end

    def navigate(event)
      if event.mouse?
        if event.mouse.kind == :press && event.mouse.button == :left
          return handle_mouse_press(event)
        end
        return :handled
      end

      menu = opened_menu
      return nil unless menu
      case event.key
      when :left
        @open_index = (@open_index - 1) % @menus.size
        @item_index = first_selectable_index(opened_menu.items) || 0
      when :right
        @open_index = (@open_index + 1) % @menus.size
        @item_index = first_selectable_index(opened_menu.items) || 0
      when :up
        @item_index = prev_selectable_index(menu.items, @item_index)
      when :down
        @item_index = next_selectable_index(menu.items, @item_index)
      when :escape, :f10
        close
      when :enter
        return activate_current
      else
        if event.char?
          activated = activate_by_hotkey(menu.items, event.key)
          return activated if activated
        end
      end
      :handled
    end

    def open_via_keyboard(event)
      if event.key == :f10
        open(0)
        return :handled
      end
      if event.alt? && event.alt_char
        idx = @menus.find_index { |m| m.hotkey == event.alt_char.downcase }
        if idx
          open(idx)
          return :handled
        end
      end
      nil
    end

    private

    def handle_mouse_press(event)
      if event.y == bounds.y
        # menubar click
        idx = @menus.find_index do |m|
          m.x && event.x >= m.x && event.x < m.x + m.display.length + 2
        end
        if idx
          @open_index == idx ? close : open(idx)
          return :handled
        end
        close
        return :handled
      end

      if open?
        menu = opened_menu
        x0   = dropdown_x(menu)
        y0   = bounds.y + 1
        w    = menu_width(menu)
        h    = menu.items.size + 2
        if event.x >= x0 && event.x < x0 + w && event.y >= y0 && event.y < y0 + h
          inner_y = event.y - y0 - 1
          if inner_y >= 0 && inner_y < menu.items.size
            item = menu.items[inner_y]
            unless item.separator || !item.enabled?
              @item_index = inner_y
              return activate_current
            end
          end
          return :handled
        end
        close
        return :handled
      end
      nil
    end

    def activate_current
      item = selected_item
      return :handled unless item&.enabled?
      close
      result = item.on_select&.call(item)
      @on_activate&.call(item)
      result == :halt ? :halt : :handled
    end

    def activate_by_hotkey(items, ch)
      down = ch.downcase
      idx = items.find_index { |i| i.enabled? && i.hotkey == down }
      return nil unless idx
      @item_index = idx
      activate_current
    end

    def first_selectable_index(items)
      items.find_index(&:enabled?)
    end

    def next_selectable_index(items, from)
      n = items.size
      i = from
      n.times do
        i = (i + 1) % n
        return i if items[i].enabled?
      end
      from
    end

    def prev_selectable_index(items, from)
      n = items.size
      i = from
      n.times do
        i = (i - 1) % n
        return i if items[i].enabled?
      end
      from
    end

    def menu_width(menu)
      max_label = menu.items.reject(&:separator).map { |i| i.display.length }.max || 0
      max_short = menu.items.reject(&:separator).map { |i| i.shortcut.to_s.length }.max || 0
      max_label + max_short + 6
    end

    # A dropdown near the right edge is shifted left so it fits the screen.
    def dropdown_x(menu)
      [[menu.x.to_i, bounds.x + bounds.width - menu_width(menu)].min, 1].max
    end

    def render_dropdown(frame)
      menu = opened_menu
      return unless menu
      x = dropdown_x(menu)
      y = bounds.y + 1
      w = menu_width(menu)
      h = menu.items.size + 2
      frame.shadow(x: x, y: y, width: w, height: h, sgr: style(:window_shadow))
      frame.box(x: x, y: y, width: w, height: h,
                sgr: style(:menu_border), fill_sgr: style(:menu_bg))

      menu.items.each_with_index do |item, idx|
        row_y = y + 1 + idx
        if item.separator
          frame.hline(x: x + 1, y: row_y, length: w - 2, char: '─', sgr: style(:menu_border))
          next
        end
        selected = (idx == @item_index)
        enabled = item.enabled?
        sgr = if !enabled
                style(:menu_disabled)
              elsif selected
                style(:menu_selected)
              else
                style(:menu_text)
              end
        frame.move(x + 1, row_y)
        frame.write(' ' * (w - 2), sgr: sgr)

        # label with hotkey highlight
        frame.move(x + 2, row_y)
        label = item.label
        idx_amp = label.index('&')
        if idx_amp && enabled
          frame.write(label[0, idx_amp], sgr: sgr)
          frame.write(label[idx_amp + 1].to_s, sgr: selected ? sgr : style(:menu_hotkey))
          rest = label[(idx_amp + 2)..]
          frame.write(rest, sgr: sgr) if rest
        else
          frame.write(item.display, sgr: sgr)
        end

        if item.shortcut
          short = item.shortcut.to_s
          frame.move(x + w - 1 - short.length, row_y)
          frame.write(short, sgr: sgr)
        end
      end
    end

    def render_hotkey_label(frame, label, x, y, sgr, hotkey_sgr)
      idx = label.index('&')
      if idx
        frame.move(x, y)
        frame.write(label[0, idx], sgr: sgr) if idx > 0
        frame.write(label[idx + 1].to_s, sgr: hotkey_sgr)
        rest = label[(idx + 2)..]
        frame.write(rest, sgr: sgr) if rest && !rest.empty?
      else
        frame.move(x, y)
        frame.write(label, sgr: sgr)
      end
    end

    class MenuBuilder
      attr_reader :items

      def initialize
        @items = []
      end

      def item(label, shortcut: nil, enabled: true, &block)
        @items << MenuItem.new(label: label, shortcut: shortcut,
                               enabled: enabled, on_select: block, separator: false)
      end

      def separator
        @items << MenuItem.new(label: '', shortcut: nil, enabled: false,
                               on_select: nil, separator: true)
      end
    end
  end
end
