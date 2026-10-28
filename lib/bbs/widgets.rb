# frozen_string_literal: true

require_relative 'widget'
require_relative 'container'

module BBS
  # The stock widgets: labels, buttons, text fields, lists, scrolling text,
  # progress indicators and layout containers. Each takes the BBS::Widget
  # keyword arguments (+id+, +bounds+, +theme+) besides its own.
  module Widgets
    # ── Label ─────────────────────────────────────────────────────────────────
    # A single line of text. The text may carry ANSI colour codes.
    class Label < Widget
      # [text]      the text shown (anything; +to_s+ is called on it)
      # [align]     +:left+, +:center+ or +:right+ within the bounds
      # [style_key] the theme role the text is drawn in
      attr_accessor :text, :align, :style_key

      # Creates a label with +text+, +align+ (default +:left+) and
      # +style_key+ (default +:text+).
      def initialize(text: '', align: :left, style_key: :text, **kw)
        super(**kw)
        @text       = text
        @align      = align
        @style_key  = style_key
      end

      # Draws the text on the first row of the bounds into +frame+, a
      # BBS::FrameBuffer, cut to the width and aligned.
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
      # [label]    the button text; an <tt>&</tt> marks the hotkey letter
      # [on_click] callable invoked as <tt>call(button)</tt> when the button
      #            fires; returning :halt ends the application
      attr_accessor :label, :on_click

      # Creates a button with +label+ (default <tt>'OK'</tt>) and +on_click+.
      def initialize(label: 'OK', on_click: nil, **kw)
        super(**kw)
        @label    = label
        @on_click = on_click
      end

      # True: a button takes the focus.
      def focusable? = true

      # The hotkey letter after the <tt>&</tt> in the label, downcased, or
      # +nil+ when the label has none.
      def hotkey
        idx = @label.index('&')
        return nil unless idx && idx + 1 < @label.length
        @label[idx + 1].downcase
      end

      # The label without its <tt>&</tt> marker.
      def display_label = @label.sub('&', '')

      # Draws the button as <tt>[ label ]</tt> centred on the first row of
      # the bounds into +frame+, in the focused, normal or disabled button
      # style, with the hotkey letter highlighted.
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
          frame.write(hot.to_s, sgr: style(:button_hotkey))
          frame.write(right, sgr: sgr)
          frame.write(' ]', sgr: sgr)
        else
          frame.write(text, sgr: sgr)
        end
      end

      # Calls +on_click+ with the button, unless the button is disabled.
      # Returns :halt when +on_click+ returned :halt, :handled otherwise.
      def fire
        return :handled if !enabled
        result = @on_click&.call(self)
        result == :halt ? :halt : :handled
      end

      # Fires the button on Enter, Space, or a left click inside its bounds;
      # returns the result of #fire. Returns +nil+ for other events and when
      # disabled.
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
    # A one-line text field that scrolls sideways when the text is wider than
    # the field.
    class TextInput < Widget
      # The current text.
      attr_reader   :value
      # [placeholder] dim text shown while the field is empty and unfocused
      # [max_length]  the most characters the field accepts
      # [on_submit]   callable invoked as <tt>call(value, input)</tt> on Enter;
      #               its result (e.g. :halt) is returned from #handle_event
      # [on_change]   callable invoked as <tt>call(value, input)</tt> after
      #               each edit
      # [password]    when true, the text is shown as asterisks
      attr_accessor :placeholder, :max_length, :on_submit, :on_change, :password

      # Creates a text field holding a copy of +value+, with the cursor at
      # its end. +max_length+ defaults to 256.
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

      # Replaces the text with <tt>text.to_s</tt> and puts the cursor at its
      # end: a cursor left past the end (after a submit clears the field)
      # would make the next key fail. Does not call +on_change+.
      def value=(text)
        @value  = text.to_s.dup
        @cursor = @value.length
        @scroll = 0
      end

      # True: a text field takes the focus.
      def focusable? = true

      # Draws the visible part of the text (or the placeholder) on the first
      # row of the bounds into +frame+, with an underscore cursor when
      # focused.
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

      # Edits the text on a key event: Left, Right, Home and End move the
      # cursor, Backspace and Delete remove a character, a printable
      # character is inserted (up to +max_length+), Enter calls +on_submit+.
      # Returns :handled (or +on_submit+'s result on Enter), and +nil+ for
      # other keys, mouse events, or when disabled, so the window gets them.
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
          # Keys it has no use for (Esc, function keys) go on to the window.
          return nil unless event.char?

          if @value.length < @max_length
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
    # A multi-line text editor. Lines are not wrapped: a line wider than the
    # area is cut off.
    class TextArea < Widget
      # Callable invoked as <tt>call(value, area)</tt> after each edit.
      attr_accessor :on_change

      # Creates an editor holding +value+ (lines separated by LF), accepting
      # at most +max_length+ characters (default 8000).
      def initialize(value: '', max_length: 8_000, on_change: nil, **kw)
        super(**kw)
        @lines      = value.empty? ? [+''] : value.split("\n", -1).map { |l| +l }
        @max_length = max_length
        @on_change  = on_change
        @cursor_r   = 0
        @cursor_c   = 0
        @scroll_r   = 0
      end

      # True: a text area takes the focus.
      def focusable? = true

      # The whole text, lines joined with LF.
      def value = @lines.join("\n")
      # The length of #value in characters.
      def length = value.length

      # Draws the visible lines into the bounds of +frame+, with an
      # underscore cursor when focused.
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

      # Edits the text on a key event: arrows move the cursor (Left and
      # Right wrap across lines), Home and End go to the line's ends, Enter
      # splits the line, Backspace deletes or joins with the line above, and
      # a printable character is inserted while #length is under
      # +max_length+. Returns :handled, or +nil+ for other keys, mouse events,
      # or when disabled.
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
          return nil unless event.char?

          if length < @max_length
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
    # A <tt>[x]</tt> / <tt>[ ]</tt> check box with a label.
    class Checkbox < Widget
      # [label]     the text after the box
      # [checked]   whether the box is ticked
      # [on_change] callable invoked as <tt>call(checked, checkbox)</tt>
      #             when the caller toggles the box
      attr_accessor :label, :checked, :on_change

      # Creates a check box with +label+, ticked when +checked+.
      def initialize(label: '', checked: false, on_change: nil, **kw)
        super(**kw)
        @label = label
        @checked = checked
        @on_change = on_change
      end

      # True: a check box takes the focus.
      def focusable? = true

      # Draws the box and label on the first row of the bounds into +frame+.
      def render(frame)
        sgr = focused ? style(:button_focused) : style(:text)
        mark = @checked ? '[x]' : '[ ]'
        text = "#{mark} #{@label}"[0, bounds.width]
        frame.move(bounds.x, bounds.y)
        frame.write(text, sgr: sgr)
      end

      # Toggles the box on Enter or Space and calls +on_change+; returns
      # :handled. Returns +nil+ for other events and when disabled.
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
    # A scrolling list of items with one selected.
    class ListBox < Widget
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

      # Moves the selection with Up, Down, Page Up, Page Down, Home and End
      # (calling +on_select+ when it changes), calls +on_activate+ on Enter,
      # selects the clicked item on a left click and scrolls the selection by
      # three on the mouse wheel. Returns :handled (or +on_activate+'s result
      # on Enter), and +nil+ for other events or when disabled.
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
      # [lines]  the Array of lines shown; they may carry ANSI colour codes
      # [scroll] index of the line on the top row
      attr_accessor :lines, :scroll

      # Creates a view of +lines+ scrolled to the top.
      def initialize(lines: [], **kw)
        super(**kw)
        @lines  = lines
        @scroll = 0
      end

      # True: a scroll view takes the focus.
      def focusable? = true

      # Draws the visible lines into the bounds of +frame+, each cut to the
      # width, and a scrollbar in the rightmost column when the lines do not
      # fit.
      def render(frame)
        return if bounds.width <= 0 || bounds.height <= 0

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

      # Scrolls with Up, Down, Page Up, Page Down, Home and End, and by three
      # lines on the mouse wheel. Returns :handled, or +nil+ for other events.
      def handle_event(event)
        max = [@lines.size - bounds.height, 0].max
        if event.mouse?
          return nil unless event.mouse.kind == :wheel
          @scroll = if event.mouse.button == :up
                      [@scroll - 3, 0].max
                    else
                      [@scroll + 3, max].min
                    end
          return :handled
        end
        return nil unless event.key?
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
    # A horizontal bar filled in proportion to +value+ / +max+.
    class ProgressBar < Widget
      # [value] the progress so far
      # [max]   the value of a full bar (a zero +max+ draws an empty bar)
      # [label] text centred on the bar, or +nil+
      attr_accessor :value, :max, :label

      # Creates a bar at +value+ out of +max+ (default 0 of 100).
      def initialize(value: 0, max: 100, label: nil, **kw)
        super(**kw)
        @value = value
        @max   = max
        @label = label
      end

      # Draws the bar on the first row of the bounds into +frame+, with the
      # label over it.
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

    # A turning spinner glyph followed by a label; call #tick to advance it.
    class Spinner < Widget
      # The spinner glyphs, shown one after another.
      FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

      # The text after the glyph.
      attr_accessor :label

      # Creates a spinner with +label+ (default <tt>'Loading...'</tt>).
      def initialize(label: 'Loading...', **kw)
        super(**kw)
        @label = label
        @frame = 0
      end

      # Advances to the next glyph of FRAMES. Returns the new frame index.
      def tick
        @frame = (@frame + 1) % FRAMES.size
      end

      # Draws the current glyph and the label on the first row of the bounds
      # into +frame+, in the accent style.
      def render(frame)
        sgr = style(:accent)
        text = "#{FRAMES[@frame]} #{@label}"
        frame.move(bounds.x, bounds.y)
        frame.write(text[0, bounds.width], sgr: sgr)
      end
    end

    # ── HBox / VBox ───────────────────────────────────────────────────────────
    # A Container that lays its children out side by side, sharing the width
    # equally.
    class HBox < Container
      # Columns left empty between two children.
      attr_accessor :gap

      # Creates an empty box with +gap+ columns between children (default 1).
      def initialize(gap: 1, **kw)
        super(**kw)
        @gap = gap
      end

      # Sets the box's bounds to +x+, +y+, +w+, +h+ and gives each child an
      # equal share of the width (less the gaps) at full height.
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

    # A Container that stacks its children top to bottom, sharing the height
    # equally.
    class VBox < Container
      # Rows left empty between two children.
      attr_accessor :gap

      # Creates an empty box with +gap+ rows between children (default 0).
      def initialize(gap: 0, **kw)
        super(**kw)
        @gap = gap
      end

      # Sets the box's bounds to +x+, +y+, +w+, +h+ and gives each child an
      # equal share of the height (less the gaps) at full width.
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
      # [title]     text shown in the top border, or +nil+
      # [box_style] the border style, +:single+ or +:double+
      attr_accessor :title, :box_style

      # Creates an empty panel with +title+ and +box_style+ (default
      # +:single+).
      def initialize(title: nil, box_style: :single, **kw)
        super(**kw)
        @title = title
        @box_style = box_style
      end

      # Sets the panel's bounds to +x+, +y+, +w+, +h+ and gives every child
      # the area inside the border (one cell in on each side). Use one child,
      # or a VBox / HBox, to place several widgets.
      def layout(x, y, w, h)
        super
        @children.each { |c| c.layout(x + 1, y + 1, [w - 2, 0].max, [h - 2, 0].max) }
      end

      # Draws the bordered, filled box over the bounds into +frame+, then the
      # children.
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
