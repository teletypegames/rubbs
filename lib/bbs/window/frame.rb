# frozen_string_literal: true

require_relative '../container'

module BBS
  class Window < Container
    # How a Window draws itself: the shadow, the frame with its title, and
    # the gadgets on it (close, number, zoom, size corner).
    module Frame
      # Draws the window into the BBS::FrameBuffer +frame+: the shadow (unless
      # maximized), the frame (double when focused or modal) with the title,
      # the close gadget <tt>[■]</tt>, the window number, the zoom gadget and
      # the size corner as they apply and fit, then the visible children.
      # While moving or sizing from the keyboard the title shows KBD_TITLES.
      def render(frame)
        render_shadow(frame)
        render_box(frame)
        render_gadgets(frame)
        @children.each { |c| c.render(frame) if c.visible }
      end

      private

      def close_gadget? = @on_close != false && bounds.width >= CLOSE_MIN_WIDTH

      def zoom_gadget? = zoomable? && bounds.width >= ZOOM_MIN_WIDTH

      def number_shown? = @number && bounds.width >= NUMBER_MIN_WIDTH

      def corner_shown? = sizable? && bounds.width >= CORNER_MIN_WIDTH

      # The column where the zoom gadget is drawn.
      def zoom_x = bounds.x + bounds.width - ZOOM_FROM_RIGHT

      def title_style = focused ? style(:window_title_focused) : style(:window_title)

      def render_shadow(frame)
        return unless @shadow && !@maximized

        frame.shadow(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
                     sgr: style(:window_shadow))
      end

      def render_box(frame)
        frame.box(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height,
                  sgr: @kbd_mode || @drag ? style(:window_title_focused) : style(:window_border),
                  fill_sgr: style(:window_bg), style: focused || @modal ? :double : :single,
                  title: shown_title, title_sgr: title_style, title_indent: close_gadget? ? TITLE_INDENT : 0)
      end

      # The title as it fits beside the gadgets, or the KBD_TITLES one.
      def shown_title
        return KBD_TITLES[@kbd_mode] if @kbd_mode
        return @title unless zoom_gadget? || number_shown?

        room = (zoom_gadget? ? TITLE_ROOM_ZOOM : TITLE_ROOM) + (number_shown? ? NUMBER_ROOM : 0)
        @title.to_s[0, [bounds.width - room, 0].max]
      end

      # Draws the gadgets that apply and fit, each <tt>[x, y, text,
      # style]</tt>.
      def render_gadgets(frame)
        [close_gadget, number_gadget, zoom_gadget, corner_gadget].compact.each do |x, y, text, sgr|
          frame.move(x, y)
          frame.write(text, sgr: sgr)
        end
      end

      def close_gadget = close_gadget? ? [bounds.x + CLOSE_X, bounds.y, '[■]', style(:window_title)] : nil

      def number_gadget = number_shown? ? [number_x, bounds.y, @number.to_s, title_style] : nil

      def zoom_gadget = zoom_gadget? ? [zoom_x, bounds.y, zoom_text, style(:window_title)] : nil

      def zoom_text = @maximized ? '[↕]' : '[↑]'

      def corner_gadget
        corner_shown? ? [bounds.x + bounds.width - 1, bounds.y + bounds.height - 1, '┘', style(:window_title)] : nil
      end

      def number_x = zoom_gadget? ? zoom_x - NUMBER_BEFORE_ZOOM : bounds.x + bounds.width - NUMBER_FROM_RIGHT
    end
  end
end
