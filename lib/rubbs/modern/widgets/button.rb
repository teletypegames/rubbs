# frozen_string_literal: true

module Rubbs
  module Modern
    module Widgets
      # A push button. Label syntax: "Save" or "&Save" (the ampersand marks
      # the hotkey letter). Pressing Alt+letter, or Enter, Space or a click
      # while focused, fires +on_click+.
      class Button < Widget
        include Drawing

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
        def hotkey = Common::Text::Hotkey.letter(@label)

        # The label without its <tt>&</tt> marker.
        def display_label = Common::Text::Hotkey.plain(@label)

        # Draws the button as <tt>[ label ]</tt> centred on the first row of
        # the bounds into +frame+, in the focused, normal or disabled button
        # style, with the hotkey letter highlighted.
        def render(frame)
          return if bounds.width <= 0

          blank(frame, 0, sgr)
          text = "[ #{display_label} ]"[0, bounds.width]
          col  = [(bounds.width - text.length) / 2, 0].max
          hotkey_parts && enabled ? put_with_hotkey(frame, col) : put(frame, col, 0, text, sgr)
        end

        # Calls +on_click+ with the button, unless the button is disabled.
        # Returns :halt when +on_click+ returned :halt, :handled otherwise.
        def fire
          return :handled unless enabled

          @on_click&.call(self) == :halt ? :halt : :handled
        end

        # Fires the button on Enter, Space, or a left click inside its bounds;
        # returns the result of #fire. Returns +nil+ for other events and when
        # disabled.
        def handle_event(event)
          return nil unless enabled
          return fire if event.key? && [:enter, ' '].include?(event.key)

          Widgets.click_in?(event, bounds) ? fire : nil
        end

        private

        def sgr
          return style(:button_disabled) unless enabled

          focused ? style(:button_focused) : style(:button)
        end

        def hotkey_parts = Common::Text::Hotkey.split(@label)

        def put_with_hotkey(frame, col)
          left, hot, right = hotkey_parts
          put(frame, col, 0, "[ #{left}", sgr)
          frame.write(hot, sgr: style(:button_hotkey))
          frame.write("#{right} ]", sgr: sgr)
        end
      end
    end
  end
end
