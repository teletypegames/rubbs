# frozen_string_literal: true

require_relative '../widgets'

module BBS
  # Ready-made window types for a BBS::Application: Info, Form,
  # MasterDetail and Stream, and the ButtonBar they share. BBS::WindowSpec
  # opens them from the +window+ DSL.
  module Windows
    # Lays out a row of buttons at the bottom of a window.
    #
    # A button descriptor is a Hash:
    #
    # [key]       a name for looking the button up in the +by_key+ result
    # [label]     the button text; +&+ marks the hotkey letter
    # [on_click]  called with the window
    # [primary]   marks the button that should get the initial focus
    # [cancel]    informational only
    # [align]     +:left+, +:right+ or +:center+
    # [keep_open] never close the window after the handler
    #
    # +on_click+ receives the BBS::Window as its only argument and may return
    # +:keep+ to keep the window open. Any other return value (or nil) causes
    # the window to be closed after the handler.
    #
    # <tt>primary: true</tt> gets initial focus on the button.
    # <tt>cancel: true</tt> is informational only: ESC closes the window
    # through the standard Window#close_key path. If you also want a
    # cancel-specific side effect on ESC, set <tt>window.on_close = ...</tt>
    # manually.
    # <tt>align: :left | :right | :center</tt>: default is +:center+ for a
    # single button, +:right+ otherwise. Left-aligned buttons stack from the
    # left edge; right-aligned buttons stack flush against the right edge in
    # declaration order (so the last right-aligned button sits closest to the
    # edge).
    #
    # The methods are module functions.
    module ButtonBar
      module_function

      # Builds a BBS::Widgets::Button for each of +descriptors+, places them
      # on the bottom row of +window+ and adds them to it. A click runs the
      # descriptor's +on_click+ and then closes the window on +app+ unless
      # it returned +:keep+ or +keep_open+ is set.
      #
      # Returns <tt>{ widgets:, primary:, by_key: }</tt>: the buttons in
      # order, the primary button (or +nil+), and a Hash of descriptor key to
      # button.
      def attach(window, app, descriptors)
        return { widgets: [], primary: nil, by_key: {} } if descriptors.nil? || descriptors.empty?

        widgets = descriptors.map do |d|
          BBS::Widgets::Button.new(label: d[:label], on_click: build_handler(window, app, d))
        end

        place(window, widgets, descriptors)

        widgets.each { |w| window.add(w) }

        primary_idx = descriptors.index { |d| d[:primary] }
        primary     = primary_idx ? widgets[primary_idx] : nil

        by_key = {}
        descriptors.each_with_index { |d, i| by_key[d[:key]] = widgets[i] if d[:key] }

        { widgets: widgets, primary: primary, by_key: by_key }
      end

      # Position (or re-position) already-built bar widgets against the
      # window's current bounds. Used by attach and by window relayouts.
      def place(window, widgets, descriptors)
        return if widgets.empty?

        default_align = descriptors.length == 1 ? :center : :right
        aligns        = descriptors.map { |d| d[:align] || default_align }

        row_y    = window.bounds.y + window.bounds.height - 2
        left_x0  = window.bounds.x + 2
        right_x1 = window.bounds.x + window.bounds.width - 2
        win_x0   = window.bounds.x
        win_w    = window.bounds.width

        x = left_x0
        widgets.each_with_index do |w, i|
          next unless aligns[i] == :left
          bw = button_width(w)
          w.layout(x, row_y, bw, 1)
          x += bw + 1
        end

        right_indices = aligns.each_index.select { |i| aligns[i] == :right }
        total_right   = right_indices.sum { |i| button_width(widgets[i]) + 1 } - 1
        total_right   = [total_right, 0].max
        x = right_x1 - total_right + 1
        right_indices.each do |i|
          bw = button_width(widgets[i])
          widgets[i].layout(x, row_y, bw, 1)
          x += bw + 1
        end

        center_indices = aligns.each_index.select { |i| aligns[i] == :center }
        total_center   = center_indices.sum { |i| button_width(widgets[i]) + 1 } - 1
        total_center   = [total_center, 0].max
        x = win_x0 + (win_w - total_center) / 2
        center_indices.each do |i|
          bw = button_width(widgets[i])
          widgets[i].layout(x, row_y, bw, 1)
          x += bw + 1
        end
      end

      # Returns the width of +button+ on screen, brackets included.
      def button_width(button)
        "[ #{button.display_label} ]".length
      end

      # Returns the click handler for +descriptor+: it calls the descriptor's
      # +on_click+ with +window+, closes the window on +app+ unless the result
      # is +:keep+ or +keep_open+ is set, and returns +:handled+.
      def build_handler(window, app, descriptor)
        on_click  = descriptor[:on_click]
        keep_open = descriptor[:keep_open]
        lambda do |_btn|
          result = on_click&.call(window)
          app.close_window(window) unless keep_open || result == :keep
          :handled
        end
      end
    end
  end
end
