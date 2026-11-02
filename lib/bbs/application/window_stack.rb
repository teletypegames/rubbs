# frozen_string_literal: true

module BBS
  class Application
    # The windows of an Application: opening and closing them, the one in
    # front, and switching between them Turbo Vision style (F6, Shift-F6,
    # Alt-1 ... Alt-9, a click on one behind).
    module WindowStack
      # The keys that cycle the windows, and which way.
      CYCLE_KEYS = { f6: 1, shift_f6: -1 }.freeze
      # An Alt-digit key, <tt>:alt_3</tt>; the group is the digit.
      ALT_DIGIT = /\Aalt_([1-9])\z/

      # Opens a window and puts it in front with the focus.
      #
      # [target] a Symbol or String naming a registered BBS::WindowSpec, or a
      #          BBS::Window to push onto the window stack as it is
      # [extras] keyword arguments passed into the spec's callback +ctx+
      #
      # A non-modal Window gets the lowest free number from 1 to 9 (for
      # Alt-digit switching). Returns the opened window. Raises ArgumentError
      # for an unknown spec name.
      def open_window(target, **extras)
        return push_window(target) if target.is_a?(Window)

        spec = @window_specs[target.to_sym]
        raise ArgumentError, "Unknown window: #{target.inspect}" unless spec

        spec.open(self, **extras)
      end

      # Brings an open window to the front and makes it the active one.
      # Returns +window+; a window that is not open is left alone.
      def raise_window(window)
        return window if window == top_window || !@windows.include?(window)

        top_window.focused = false
        @windows.delete(window)
        @windows << window
        window.focused = true
        window
      end

      # Returns the windows the caller can switch between, sorted by their
      # number. Empty while a modal window (a dialog) is open: it keeps the
      # front.
      def switchable_windows
        return [] if @windows.any?(&:modal)

        @windows.reject(&:modal).sort_by { |w| w.number || UNNUMBERED }
      end

      # Brings the next (+step+ 1, F6) or previous (+step+ -1, Shift-F6)
      # switchable window to the front, by number. Returns the raised window,
      # or +nil+ when fewer than two windows can be switched.
      def cycle_windows(step = 1)
        list = switchable_windows
        return nil if list.size < 2

        index = list.index(top_window) || 0
        raise_window(list[(index + step) % list.size])
      end

      # Removes +window+ (default: the top one) from the window stack, gives
      # the focus to the new top window and calls the window's +on_close+ with
      # it when that is callable. Returns +nil+ when no window is open.
      def close_window(window = nil)
        window ||= @windows.last
        return unless window

        @windows.delete(window)
        window.focused = false
        top_window&.focused = true
        window.on_close.call(window) if window.on_close.respond_to?(:call)
      end

      # The window in front, or +nil+ when none is open.
      def top_window = @windows.last

      private

      # Puts +window+ in front with the application's theme and a number.
      def push_window(window)
        window.theme  = @theme
        window.app    = self
        window.number = free_number unless window.modal
        top_window&.focused = false
        @windows << window
        window.focused = true
        window
      end

      def free_number
        taken = @windows.filter_map(&:number)
        WINDOW_NUMBERS.find { |n| !taken.include?(n) }
      end

      # F6, Shift-F6 and Alt-digit switch windows; a click on a window behind
      # the top one brings it to the front, and the click goes on to it, so a
      # button or the title bar answers at once. Returns +:handled+ when a
      # key was taken, +nil+ otherwise.
      def switch_window(event)
        return nil if top_window&.busy?
        return switch_key(event.key) if event.key?

        raise_clicked(event) if event.mouse? && event.mouse.kind == :press
        nil
      end

      def switch_key(key)
        return cycle_windows(CYCLE_KEYS[key]) && :handled if CYCLE_KEYS.key?(key)

        number = key.to_s[ALT_DIGIT, 1]
        target = number && switchable_windows.find { |w| w.number == number.to_i }
        target && raise_window(target) && :handled
      end

      def raise_clicked(event)
        target = @windows.reverse.find { |w| w.bounds.contains?(event.x, event.y) }
        raise_window(target) if target && switchable_windows.include?(target)
      end
    end
  end
end
