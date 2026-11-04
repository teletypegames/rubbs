# frozen_string_literal: true

module BBS
  module Widgets
    # A one-line text field that scrolls sideways when the text is wider than
    # the field.
    class TextInput < Widget
      include Drawing

      # The editing keys and the method each one calls.
      KEYS = {
        left:      :left,
        right:     :right,
        home:      :to_start,
        end:       :to_end,
        backspace: :backspace,
        delete:    :delete,
        enter:     :submit
      }.freeze

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
      def initialize(
        value: '',
        placeholder: '',
        max_length: 256,
        on_submit: nil,
        on_change: nil,
        password: false,
        **kw
      )
        super(**kw)
        @placeholder = placeholder
        @max_length  = max_length
        @on_submit   = on_submit
        @on_change   = on_change
        @password    = password
        self.value   = value
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
        return if no_room?

        blank(frame, 0, sgr)
        if placeholder?
          put(frame, 0, 0, @placeholder[0, bounds.width - 1].to_s, style(:text_dim))
        else
          put(frame, 0, 0, shown_text, sgr)
        end
        draw_cursor(frame) if focused
      end

      # Edits the text on a key event: Left, Right, Home and End move the
      # cursor, Backspace and Delete remove a character, a printable
      # character is inserted (up to +max_length+), Enter calls +on_submit+.
      # Returns :handled (or +on_submit+'s result on Enter), and +nil+ for
      # other keys, mouse events, or when disabled, so the window gets them.
      def handle_event(event)
        return nil unless event.key? && enabled
        return send(KEYS[event.key]) if KEYS.key?(event.key)

        event.char? ? insert(event.key) : nil
      end

      private

      def sgr = focused ? style(:input_focused) : style(:input)

      def shown_text = (@password ? '*' * @value.length : @value)[@scroll, bounds.width - 1] || ''

      def placeholder? = shown_text.empty? && !focused && !@placeholder.empty?

      def draw_cursor(frame)
        put(frame, [@cursor - @scroll, bounds.width - 1].min, 0, '_', sgr)
      end

      # Puts the cursor at +position+, kept in the text, and scrolls to it.
      def cursor_to(position)
        @cursor = position.clamp(0, @value.length)
        adjust_scroll
        :handled
      end

      def left = cursor_to(@cursor - 1)

      def right = cursor_to(@cursor + 1)

      def to_start
        @scroll = 0
        cursor_to(0)
      end

      def to_end = cursor_to(@value.length)

      def backspace
        return :handled unless @cursor.positive?

        @value.slice!(@cursor - 1)
        cursor_to(@cursor - 1)
        changed
      end

      def delete
        return :handled unless @cursor < @value.length

        @value.slice!(@cursor)
        changed
      end

      def submit = @on_submit ? @on_submit.call(@value, self) || :handled : :handled

      def insert(char)
        return :handled unless @value.length < @max_length

        @value.insert(@cursor, char)
        cursor_to(@cursor + 1)
        changed
      end

      def changed
        @on_change&.call(@value, self)
        :handled
      end

      def adjust_scroll
        view_width = bounds.width - 1
        @scroll = @cursor if @cursor < @scroll
        @scroll = @cursor - view_width + 1 if @cursor >= @scroll + view_width
        @scroll = [@scroll, 0].max
      end
    end
  end
end
