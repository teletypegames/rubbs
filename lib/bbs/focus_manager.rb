# frozen_string_literal: true

module BBS
  # Tracks which widget within a Container currently has focus.
  # Tab / Shift-Tab cycle through its focusable descendants.
  class FocusManager
    # The widget that has the focus, or +nil+.
    attr_reader :focused

    # Creates a manager for +container+, a BBS::Container, and focuses its
    # first candidate.
    def initialize(container)
      @container = container
      @focused   = nil
      focus_first
    end

    # Returns the widgets that can take the focus: the container's visible,
    # focusable and enabled descendants, in walk order.
    def candidates
      @container.focusable_descendants.select { |w| w.enabled }
    end

    # Moves the focus to the first candidate, or clears it when there is none.
    def focus_first
      first = candidates.first
      set_focus(first)
    end

    # Moves the focus to +widget+ when it is focusable and enabled; otherwise
    # leaves the focus where it is. The old widget gets +on_blur+, the new
    # one +on_focus+.
    def focus(widget)
      set_focus(widget) if widget && widget.focusable? && widget.enabled
    end

    # Moves the focus to the next candidate, wrapping around at the end.
    def next_focus
      list = candidates
      return if list.empty?
      idx = list.index(@focused) || -1
      set_focus(list[(idx + 1) % list.size])
    end

    # Moves the focus to the previous candidate, wrapping around at the start.
    def prev_focus
      list = candidates
      return if list.empty?
      idx = list.index(@focused) || 0
      set_focus(list[(idx - 1) % list.size])
    end

    # Handles Tab (next) and Shift-Tab (previous) in +event+, a BBS::Event.
    #
    # Returns +true+ when the key moved the focus, +false+ otherwise.
    def handle_focus_key(event)
      return false unless event.key?
      case event.key
      when :tab
        next_focus
        true
      when :shift_tab
        prev_focus
        true
      else
        false
      end
    end

    # Passes +event+ to the focused widget's +handle_event+.
    #
    # Returns the widget's result, or +nil+ when nothing has the focus.
    def dispatch(event)
      return nil unless @focused
      @focused.handle_event(event)
    end

    private

    def set_focus(widget)
      return if widget == @focused
      if @focused
        @focused.focused = false
        @focused.on_blur
      end
      @focused = widget
      if widget
        widget.focused = true
        widget.on_focus
      end
    end
  end
end
