# frozen_string_literal: true

module BBS
  # Tracks which widget within a Container currently has focus.
  # Tab / Shift-Tab cycle through its focusable descendants.
  class FocusManager
    attr_reader :focused

    def initialize(container)
      @container = container
      @focused   = nil
      focus_first
    end

    def candidates
      @container.focusable_descendants.select { |w| w.enabled }
    end

    def focus_first
      first = candidates.first
      set_focus(first)
    end

    def focus(widget)
      set_focus(widget) if widget && widget.focusable? && widget.enabled
    end

    def next_focus
      list = candidates
      return if list.empty?
      idx = list.index(@focused) || -1
      set_focus(list[(idx + 1) % list.size])
    end

    def prev_focus
      list = candidates
      return if list.empty?
      idx = list.index(@focused) || 0
      set_focus(list[(idx - 1) % list.size])
    end

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
