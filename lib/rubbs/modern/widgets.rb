# frozen_string_literal: true

require_relative 'widgets/widget'
require_relative 'widgets/container'
require_relative '../common/text/hotkey'

module Rubbs
  module Modern
    # The stock widgets: labels, buttons, text fields, check boxes, lists and
    # scrolling text, one class per file under +widgets/+. Each takes the
    # Rubbs::Modern::Widgets::Widget keyword arguments (+id+, +bounds+, +theme+) besides its own.
    module Widgets
      # The mouse wheel's step: the rows a list or a view moves per notch.
      WHEEL_STEP = 3

      # Whether +event+ is a left click inside +bounds+.
      def self.click_in?(event, bounds)
        event.mouse? && event.mouse.kind == :press && event.mouse.button == :left && bounds.contains?(event.x, event.y)
      end

      # The rows the mouse wheel of +event+ moves inside +bounds+: minus
      # WHEEL_STEP up, WHEEL_STEP down; +nil+ for any other event.
      def self.wheel(event, bounds)
        return nil unless event.mouse? && event.mouse.kind == :wheel && bounds.contains?(event.x, event.y)

        event.mouse.button == :up ? -WHEEL_STEP : WHEEL_STEP
      end

      # Drawing inside a widget's bounds, its columns and rows counted from
      # 0 at the top left: what the stock widgets include.
      module Drawing
        private

        # Writes +text+ at column +col+ of row +row+ in style +sgr+.
        def put(frame, col, row, text, sgr)
          frame.move(bounds.x + col, bounds.y + row)
          frame.write(text, sgr: sgr)
        end

        # Writes the ANSI +text+ at column +col+ of row +row+ over the style
        # +sgr+.
        def put_ansi(frame, col, row, text, sgr)
          frame.move(bounds.x + col, bounds.y + row)
          frame.write_ansi(text, base_sgr: sgr)
        end

        # Fills row +row+ with spaces in style +sgr+.
        def blank(frame, row, sgr) = put(frame, 0, row, ' ' * bounds.width, sgr)

        # Whether the bounds have no room to draw in.
        def no_room? = bounds.width <= 0 || bounds.height <= 0
      end
    end
  end
end

require_relative 'widgets/label'
require_relative 'widgets/button'
require_relative 'widgets/text_input'
require_relative 'widgets/text_area'
require_relative 'widgets/checkbox'
require_relative 'widgets/list_box'
require_relative 'widgets/scroll_view'
