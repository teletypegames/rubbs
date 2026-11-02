# frozen_string_literal: true

module BBS
  module Widgets
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
        frame.move(bounds.x, bounds.y)
        frame.write("#{@checked ? '[x]' : '[ ]'} #{@label}"[0, bounds.width], sgr: sgr)
      end

      # Toggles the box on Enter or Space and calls +on_change+; returns
      # :handled. Returns +nil+ for other events and when disabled.
      def handle_event(event)
        return nil unless enabled && event.key? && [:enter, ' '].include?(event.key)

        @checked = !@checked
        @on_change&.call(@checked, self)
        :handled
      end
    end
  end
end
