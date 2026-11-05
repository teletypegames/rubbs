# frozen_string_literal: true

module Rubbs
  module Modern
    module Widgets
      # Tracks which widget within a Container currently has focus.
      # Tab / Shift-Tab cycle through its focusable descendants.
      class FocusManager
        # The widget that has the focus, or +nil+.
        attr_reader :focused

        # Creates a manager for +container+, a Rubbs::Modern::Widgets::Container, and focuses its
        # first candidate.
        def initialize(container)
          @container = container
          @focused   = nil
          focus_first
        end

        # Returns the widgets that can take the focus: the container's visible,
        # focusable and enabled descendants, in walk order.
        def candidates
          @container.focusable_descendants.select(&:enabled)
        end

        # Moves the focus to the first candidate, or clears it when there is none.
        def focus_first
          move_focus(candidates.first)
        end

        # Moves the focus to +widget+ when it is focusable and enabled; otherwise
        # leaves the focus where it is. The old widget gets +on_blur+, the new
        # one +on_focus+.
        def focus(widget)
          move_focus(widget) if widget&.focusable? && widget.enabled
        end

        # Moves the focus to the next candidate, wrapping around at the end.
        def next_focus = step_focus(1, -1)

        # Moves the focus to the previous candidate, wrapping around at the start.
        def prev_focus = step_focus(-1, 0)

        # The focus moves of Tab and Shift-Tab.
        FOCUS_KEYS = { tab: :next_focus, shift_tab: :prev_focus }.freeze

        # Handles Tab (next) and Shift-Tab (previous) in +event+, a Rubbs::Modern::Widgets::Event.
        #
        # Returns +:handled+ when the key moved the focus, +nil+ otherwise.
        def handle_focus_key(event)
          move = event.key? && FOCUS_KEYS[event.key]
          return nil unless move

          public_send(move)
          :handled
        end

        # Passes +event+ to the focused widget's +handle_event+.
        #
        # Returns the widget's result, or +nil+ when nothing has the focus.
        def dispatch(event)
          return nil unless @focused

          @focused.handle_event(event)
        end

        private

        # The candidate +by+ places from the focused one (from +none+ when
        # nothing has the focus), round the ends.
        def step_focus(by, none)
          list = candidates
          return if list.empty?

          move_focus(list[((list.index(@focused) || none) + by) % list.size])
        end

        def move_focus(widget)
          return if widget == @focused

          @focused&.focused = false
          @focused&.on_blur
          @focused = widget
          widget&.focused = true
          widget&.on_focus
        end
      end
    end
  end
end
