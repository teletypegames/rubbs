# frozen_string_literal: true

require_relative '../widgets/container'

module Rubbs
  module Modern
    class Window < Widgets::Container
      # How a Window takes a keyboard or mouse event: a chain of small
      # handlers, each returning +nil+ when it leaves the event to the next.
      module Events
        # The handlers #handle_event tries in order.
        HANDLERS = %i[
          moving_key_event drag_event zoom_key_event move_key_event click_event wheel_event focus_event
          hotkey_event close_key_event
        ].freeze

        # Handles a keyboard or mouse event for the window, in this order:
        # keyboard move/size mode, an ongoing mouse drag, the ZOOM_KEYS and
        # MOVE_KEYS, left clicks on the gadgets, title bar and size corner (a
        # click elsewhere focuses the focusable widget under it), wheel events
        # for the widget under the pointer, focus keys and the focused widget
        # (a modified arrow or paging key nothing took is retried plain), a
        # button hotkey, and finally +close_key+.
        #
        # Returns +:close_window+ when the window should close, +:halt+ or
        # +:handled+ as the widgets return them, or +nil+ when nothing used the
        # event.
        def handle_event(event)
          HANDLERS.each do |handler|
            result = send(handler, event)
            return result if result
          end
          nil
        end

        private

        def moving_key_event(event) = @kbd_mode && keyboard_move(event)

        def drag_event(event) = @drag && event.mouse? && drag(event)

        def zoom_key_event(event) = event.key? && zoomable? && ZOOM_KEYS.include?(event.key) && toggle_maximize

        def move_key_event(event)
          return nil unless event.key? && MOVE_KEYS.include?(event.key) && movable?

          @kbd_mode = :move
          :handled
        end

        # A left click on a gadget, the title bar or the size corner; a click
        # elsewhere focuses the focusable widget under it and goes on.
        def click_event(event)
          return nil unless event.click?

          frame_click(event) || focus_at(event.x, event.y)
        end

        def frame_click(event)
          return close if close_gadget_at?(event.x, event.y)
          return toggle_maximize if zoom_click?(event)
          return start_drag(:size, event) if sizable? && corner?(event)

          start_drag(:move, event) if movable? && event.y == bounds.y
        end

        # Focuses the focusable widget at +x+, +y+, if any. Returns +nil+: the
        # click goes on to the widget.
        def focus_at(x, y)
          hit = hit_test(x, y)
          focus_manager.focus(hit) if hit&.focusable?
          nil
        end

        # Wheel scrolling goes to the widget under the pointer, so a scrolling
        # pane answers even when the keyboard focus is elsewhere.
        def wheel_event(event)
          return nil unless event.mouse? && event.mouse.kind == :wheel

          hit = hit_test(event.x, event.y)
          hit.handle_event(event) if hit && hit != self && hit != focus_manager.focused
        end

        # The focus keys, then the focused widget; a modified key nothing
        # takes (Shift-Down in a list) acts as the plain key.
        def focus_event(event)
          focus_manager.handle_focus_key(event) || focus_manager.dispatch(event) || plain_key(event)
        end

        def plain_key(event)
          plain = event.key? && event.key.to_s[MODIFIED_MOVE_KEY, 1]
          focus_manager.dispatch(Widgets::Event.key(plain.to_sym)) if plain
        end

        # A key the focused widget left alone presses the button it is the
        # hotkey of: "y" or Alt-Y for "&Yes".
        def hotkey_event(event)
          hotkey_button(event.key)&.fire if event.key?
        end

        def close_key_event(event) = event.key? && event.key == @close_key ? close : nil

        # Whether +x+, +y+ is on the close gadget.
        def close_gadget_at?(x, y)
          @on_close != false && y == bounds.y && x.between?(bounds.x + CLOSE_X, bounds.x + CLOSE_X + GADGET_WIDTH - 1)
        end

        # The enabled Widgets::Button in the window whose hotkey matches +key+
        # (a single character or an +alt_+ letter Symbol), or +nil+.
        def hotkey_button(key)
          letter = key.is_a?(String) && key.length == 1 ? key.downcase : key.to_s[ALT_KEY, 1]
          return nil unless letter

          focusable_descendants.find { |w| w.is_a?(Widgets::Button) && w.enabled && w.hotkey == letter }
        end
      end
    end
  end
end
