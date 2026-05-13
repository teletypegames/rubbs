# frozen_string_literal: true

require_relative 'widget'
require_relative 'container'

module BBS
  module Widgets
    # ── Label ─────────────────────────────────────────────────────────────────
    class Label < Widget
      attr_accessor :text, :align, :style_key

      def initialize(text: '', align: :left, style_key: :text, **kw)
        super(**kw)
        @text       = text
        @align      = align
        @style_key  = style_key
      end

      def render(frame)
        return if bounds.width <= 0
        line  = @text.to_s
        clipped = line[0, bounds.width].to_s
        x = case @align
            when :center then bounds.x + ([bounds.width - clipped.length, 0].max / 2)
            when :right  then bounds.x + bounds.width - clipped.length
            else              bounds.x
            end
        frame.move(x, bounds.y)
        frame.write_ansi(clipped, base_sgr: style(@style_key))
      end
    end

    # ── Button ────────────────────────────────────────────────────────────────
    # Label syntax: "Save" or "&Save" (ampersand marks the hotkey letter).
    # Pressing Alt+letter or Enter (when focused) fires on_click.
    class Button < Widget
      attr_accessor :label, :on_click

      def initialize(label: 'OK', on_click: nil, **kw)
        super(**kw)
        @label    = label
        @on_click = on_click
      end

      def focusable? = true

      def hotkey
        idx = @label.index('&')
        return nil unless idx && idx + 1 < @label.length
        @label[idx + 1].downcase
      end

      def display_label = @label.sub('&', '')

      def render(frame)
        return if bounds.width <= 0
        sgr     = focused ? style(:button_focused) : style(:button)
        sgr     = style(:button_disabled) unless enabled
        text    = "[ #{display_label} ]"
        text    = text[0, bounds.width]
        frame.move(bounds.x, bounds.y)
        frame.write(' ' * bounds.width, sgr: sgr)
        frame.move(bounds.x + [(bounds.width - text.length) / 2, 0].max, bounds.y)
        # write with hotkey highlighting
        idx = @label.index('&')
        if idx && enabled
          left  = @label[0, idx]
          hot   = @label[idx + 1]
          right = @label[(idx + 2)..] || ''
          frame.write('[ ', sgr: sgr)
          frame.write(left, sgr: sgr) unless left.empty?
          frame.write(hot, sgr: style(:button_hotkey))
          frame.write(right, sgr: sgr)
          frame.write(' ]', sgr: sgr)
        else
          frame.write(text, sgr: sgr)
        end
      end

      def fire
        return :handled if !enabled
        result = @on_click&.call(self)
        result == :halt ? :halt : :handled
      end

      def handle_event(event)
        return nil unless enabled
        if event.key?
          return fire if event.key == :enter || event.key == ' '
        elsif event.mouse?
          if event.mouse.kind == :press && event.mouse.button == :left &&
             bounds.contains?(event.x, event.y)
            return fire
          end
        end
        nil
      end
    end

    # ── TextInput ─────────────────────────────────────────────────────────────
    class TextInput < Widget
      attr_accessor :value, :placeholder, :max_length, :on_submit, :on_change, :password

      def initialize(value: '', placeholder: '', max_length: 256,
                     on_submit: nil, on_change: nil, password: false, **kw)
        super(**kw)
        @value       = value.dup
        @placeholder = placeholder
        @max_length  = max_length
        @on_submit   = on_submit
        @on_change   = on_change
        @password    = password
        @cursor      = @value.length
        @scroll      = 0
      end

      def focusable? = true

      def render(frame)
        return if bounds.width <= 0 || bounds.height <= 0
        sgr = focused ? style(:input_focused) : style(:input)
        frame.move(bounds.x, bounds.y)
        frame.write(' ' * bounds.width, sgr: sgr)

        display = @password ? '*' * @value.length : @value
        visible = display[@scroll, bounds.width - 1] || ''
        frame.move(bounds.x, bounds.y)
        if visible.empty? && !focused && !@placeholder.empty?
          ph = @placeholder[0, bounds.width - 1].to_s
          frame.write(ph, sgr: style(:text_dim))
        else
          frame.write(visible, sgr: sgr)
        end

        if focused
          cx = bounds.x + (@cursor - @scroll)
          cx = bounds.x + bounds.width - 1 if cx >= bounds.x + bounds.width
          frame.move(cx, bounds.y)
          frame.write('_', sgr: sgr)
        end
      end

      def handle_event(event)
        return nil unless event.key? && enabled
        case event.key
        when :left
          @cursor = [@cursor - 1, 0].max
          adjust_scroll
        when :right
          @cursor = [@cursor + 1, @value.length].min
          adjust_scroll
        when :home
          @cursor = 0; @scroll = 0
        when :end
          @cursor = @value.length; adjust_scroll
        when :backspace
          if @cursor > 0
            @value.slice!(@cursor - 1)
            @cursor -= 1
            adjust_scroll
            @on_change&.call(@value, self)
          end
        when :delete
          if @cursor < @value.length
            @value.slice!(@cursor)
            @on_change&.call(@value, self)
          end
        when :enter
          return @on_submit ? @on_submit.call(@value, self) || :handled : :handled
        else
          if event.char? && @value.length < @max_length
            @value.insert(@cursor, event.key)
            @cursor += 1
            adjust_scroll
            @on_change&.call(@value, self)
            return :handled
          end
        end
        :handled
      end

      private

      def adjust_scroll
        view_width = bounds.width - 1
        @scroll = @cursor if @cursor < @scroll
        @scroll = @cursor - view_width + 1 if @cursor >= @scroll + view_width
        @scroll = [@scroll, 0].max
      end
    end

    # ── TextArea ──────────────────────────────────────────────────────────────
    class TextArea < Widget
      attr_accessor :on_change

      def initialize(value: '', max_length: 8_000, on_change: nil, **kw)
        super(**kw)
        @lines      = value.empty? ? [+''] : value.split("\n", -1).map { |l| +l }
        @max_length = max_length
        @on_change  = on_change
        @cursor_r   = 0
        @cursor_c   = 0
        @scroll_r   = 0
      end

      def focusable? = true

      def value = @lines.join("\n")
      def length = value.length

      def render(frame)
        return if bounds.width <= 0 || bounds.height <= 0
        sgr = focused ? style(:input_focused) : style(:input)
        bounds.height.times do |r|
          frame.move(bounds.x, bounds.y + r)
          frame.write(' ' * bounds.width, sgr: sgr)
          line = @lines[@scroll_r + r]
          next unless line
          frame.move(bounds.x, bounds.y + r)
          frame.write(line[0, bounds.width].to_s, sgr: sgr)
        end
        if focused
          cy = bounds.y + (@cursor_r - @scroll_r)
          cx = bounds.x + [@cursor_c, bounds.width - 1].min
          if cy >= bounds.y && cy < bounds.y + bounds.height
            frame.move(cx, cy)
            frame.write('_', sgr: sgr)
          end
        end
      end

      def handle_event(event)
        return nil unless event.key? && enabled
        case event.key
        when :left  then move_cursor(-1, :col)
        when :right then move_cursor(1,  :col)
        when :up    then move_cursor(-1, :row)
        when :down  then move_cursor(1,  :row)
        when :home  then @cursor_c = 0
        when :end   then @cursor_c = @lines[@cursor_r].length
        when :enter
          tail = +(@lines[@cursor_r][@cursor_c..] || '')
          @lines[@cursor_r] = +(@lines[@cursor_r][0, @cursor_c] || '')
          @lines.insert(@cursor_r + 1, tail)
          @cursor_r += 1
          @cursor_c = 0
          ensure_visible
          @on_change&.call(value, self)
        when :backspace
          if @cursor_c > 0
            @lines[@cursor_r].slice!(@cursor_c - 1)
            @cursor_c -= 1
          elsif @cursor_r > 0
            prev_len = @lines[@cursor_r - 1].length
            @lines[@cursor_r - 1] += @lines.delete_at(@cursor_r)
            @cursor_r -= 1
            @cursor_c = prev_len
            ensure_visible
          end
          @on_change&.call(value, self)
        else
          if event.char? && length < @max_length
            @lines[@cursor_r].insert(@cursor_c, event.key)
            @cursor_c += 1
            @on_change&.call(value, self)
            return :handled
          end
        end
        :handled
      end

      private

      def move_cursor(delta, axis)
        if axis == :col
          @cursor_c += delta
          if @cursor_c < 0 && @cursor_r > 0
            @cursor_r -= 1
            @cursor_c = @lines[@cursor_r].length
          elsif @cursor_c > @lines[@cursor_r].length && @cursor_r < @lines.size - 1
            @cursor_r += 1
            @cursor_c = 0
          end
          @cursor_c = @cursor_c.clamp(0, @lines[@cursor_r].length)
        else
          @cursor_r = (@cursor_r + delta).clamp(0, @lines.size - 1)
          @cursor_c = @cursor_c.clamp(0, @lines[@cursor_r].length)
        end
        ensure_visible
      end

      def ensure_visible
        @scroll_r = @cursor_r if @cursor_r < @scroll_r
        @scroll_r = @cursor_r - bounds.height + 1 if @cursor_r >= @scroll_r + bounds.height
        @scroll_r = [@scroll_r, 0].max
      end
    end

    # ── Checkbox ──────────────────────────────────────────────────────────────
    class Checkbox < Widget
      attr_accessor :label, :checked, :on_change

      def initialize(label: '', checked: false, on_change: nil, **kw)
        super(**kw)
        @label = label
        @checked = checked
        @on_change = on_change
      end

      def focusable? = true

      def render(frame)
        sgr = focused ? style(:button_focused) : style(:text)
        mark = @checked ? '[x]' : '[ ]'
        text = "#{mark} #{@label}"[0, bounds.width]
        frame.move(bounds.x, bounds.y)
        frame.write(text, sgr: sgr)
      end

      def handle_event(event)
        return nil unless enabled && event.key?
        if event.key == :enter || event.key == ' '
          @checked = !@checked
          @on_change&.call(@checked, self)
          return :handled
        end
        nil
      end
    end

    # ── ListBox ───────────────────────────────────────────────────────────────
    class ListBox < Widget
      attr_accessor :items, :selected, :scroll, :on_select, :on_activate, :label

      def initialize(items: [], on_select: nil, on_activate: nil, label: nil, **kw)
        super(**kw)
        @items       = items
        @selected    = 0
        @scroll      = 0
        @on_select   = on_select
        @on_activate = on_activate
        @label       = label
      end

      def focusable? = true
      def selected_item = @items[@selected]

      def render(frame)
        return if bounds.width <= 0 || bounds.height <= 0
        bg = style(:listbox)
        bounds.height.times do |r|
          idx = @scroll + r
          frame.move(bounds.x, bounds.y + r)
          frame.write(' ' * bounds.width, sgr: bg)
          item = @items[idx]
          next unless item
          text = (@label ? @label.call(item) : item.to_s)[0, bounds.width]
          line_sgr = if idx == @selected
                       focused ? style(:listbox_focused) : style(:listbox_selected)
                     else
                       bg
                     end
          frame.move(bounds.x, bounds.y + r)
          frame.write(' ' * bounds.width, sgr: line_sgr) if idx == @selected
          frame.move(bounds.x, bounds.y + r)
          frame.write(text, sgr: line_sgr)
        end
      end

      def handle_event(event)
        return nil unless enabled
        if event.key?
          case event.key
          when :up         then move(-1)
          when :down       then move(1)
          when :page_up    then move(-bounds.height)
          when :page_down  then move(bounds.height)
          when :home       then move_to(0)
          when :end        then move_to(@items.size - 1)
          when :enter      then return @on_activate&.call(selected_item, self) || :handled
          else return nil
          end
          :handled
        elsif event.mouse?
          if event.mouse.kind == :press && event.mouse.button == :left &&
             bounds.contains?(event.x, event.y)
            row = event.y - bounds.y
            idx = @scroll + row
            if idx < @items.size
              prev = @selected
              @selected = idx
              @on_select&.call(selected_item, self) if prev != idx
            end
            return :handled
          elsif event.mouse.kind == :wheel && bounds.contains?(event.x, event.y)
            event.mouse.button == :up ? move(-3) : move(3)
            return :handled
          end
          nil
        end
      end

      private

      def move(delta)
        return if @items.empty?
        prev = @selected
        @selected = (@selected + delta).clamp(0, @items.size - 1)
        adjust_scroll
        @on_select&.call(selected_item, self) if prev != @selected
      end

      def move_to(idx)
        return if @items.empty?
        prev = @selected
        @selected = idx.clamp(0, @items.size - 1)
        adjust_scroll
        @on_select&.call(selected_item, self) if prev != @selected
      end

      def adjust_scroll
        @scroll = @selected if @selected < @scroll
        @scroll = @selected - bounds.height + 1 if @selected >= @scroll + bounds.height
        @scroll = [@scroll, 0].max
      end
    end

    # ── ScrollView: a scrollable text buffer (lines: Array[String]) ───────────
    class ScrollView < Widget
      attr_accessor :lines, :scroll

      def initialize(lines: [], **kw)
        super(**kw)
        @lines  = lines
        @scroll = 0
      end

      def focusable? = true

      def render(frame)
        sgr = style(:text)
        bounds.height.times do |r|
          frame.move(bounds.x, bounds.y + r)
          frame.write(' ' * bounds.width, sgr: sgr)
          line = @lines[@scroll + r]
          next unless line
          frame.move(bounds.x, bounds.y + r)
          frame.write_ansi(FrameBuffer.clip_ansi(line.to_s, bounds.width), base_sgr: sgr)
        end
        # right-side scrollbar
        if @lines.size > bounds.height && bounds.width > 1
          track_h = bounds.height
          thumb_y = bounds.y + (@scroll * (track_h - 1).to_f / [@lines.size - bounds.height, 1].max).to_i
          frame.vline(x: bounds.x + bounds.width - 1, y: bounds.y, length: track_h,
                      char: '│', sgr: style(:scrollbar))
          frame.move(bounds.x + bounds.width - 1, thumb_y)
          frame.write('█', sgr: style(:scrollbar_thumb))
        end
      end

      def handle_event(event)
        return nil unless event.key?
        max = [@lines.size - bounds.height, 0].max
        case event.key
        when :up        then @scroll = [@scroll - 1, 0].max
        when :down      then @scroll = [@scroll + 1, max].min
        when :page_up   then @scroll = [@scroll - bounds.height, 0].max
        when :page_down then @scroll = [@scroll + bounds.height, max].min
        when :home      then @scroll = 0
        when :end       then @scroll = max
        else return nil
        end
        :handled
      end
    end

    # ── ProgressBar / Spinner ─────────────────────────────────────────────────
    class ProgressBar < Widget
      attr_accessor :value, :max, :label

      def initialize(value: 0, max: 100, label: nil, **kw)
        super(**kw)
        @value = value
        @max   = max
        @label = label
      end

      def render(frame)
        sgr  = style(:text)
        fill = style(:button_focused)
        return if bounds.width <= 0
        ratio = @max.zero? ? 0.0 : @value.to_f / @max
        bars  = (ratio * bounds.width).to_i.clamp(0, bounds.width)
        frame.move(bounds.x, bounds.y)
        frame.write('█' * bars, sgr: fill)
        frame.write('░' * (bounds.width - bars), sgr: sgr)
        if @label
          text = @label[0, bounds.width]
          frame.move(bounds.x + (bounds.width - text.length) / 2, bounds.y)
          frame.write_ansi(text, base_sgr: sgr)
        end
      end
    end

    class Spinner < Widget
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      attr_accessor :label

      def initialize(label: 'Loading...', **kw)
        super(**kw)
        @label = label
        @frame = 0
      end

      def tick
        @frame = (@frame + 1) % FRAMES.size
      end

      def render(frame)
        sgr = style(:accent)
        text = "#{FRAMES[@frame]} #{@label}"
        frame.move(bounds.x, bounds.y)
        frame.write(text[0, bounds.width], sgr: sgr)
      end
    end

    # ── HBox / VBox ───────────────────────────────────────────────────────────
    class HBox < Container
      attr_accessor :gap

      def initialize(gap: 1, **kw)
        super(**kw)
        @gap = gap
      end

      def layout(x, y, w, h)
        super
        return if @children.empty?
        per = ((w - (@children.size - 1) * @gap) / @children.size.to_f)
        cx = x
        @children.each_with_index do |c, i|
          width = (per * (i + 1)).to_i - (per * i).to_i
          c.layout(cx, y, width, h)
          cx += width + @gap
        end
      end
    end

    class VBox < Container
      attr_accessor :gap

      def initialize(gap: 0, **kw)
        super(**kw)
        @gap = gap
      end

      def layout(x, y, w, h)
        super
        return if @children.empty?
        per = ((h - (@children.size - 1) * @gap) / @children.size.to_f)
        cy = y
        @children.each_with_index do |c, i|
          height = (per * (i + 1)).to_i - (per * i).to_i
          c.layout(x, cy, w, height)
          cy += height + @gap
        end
      end
    end

    # ── Panel: a Container with a border and optional title ──────────────────
    class Panel < Container
      attr_accessor :title, :box_style

      def initialize(title: nil, box_style: :single, **kw)
        super(**kw)
        @title = title
        @box_style = box_style
      end

      def render(frame)
        frame.box(
          x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
          sgr: style(:window_border), fill_sgr: style(:window_bg),
          style: @box_style, title: @title, title_sgr: style(:window_title),
        )
        super
      end
    end
  end
end
