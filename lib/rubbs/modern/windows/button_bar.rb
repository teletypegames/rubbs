# frozen_string_literal: true

require_relative '../widgets'

module Rubbs
  module Modern
    # Ready-made window types for a Rubbs::Modern::Application: Info, Form,
    # MasterDetail and Stream, and the ButtonBar they share. Rubbs::Modern::WindowSpec
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
      # +on_click+ receives the Rubbs::Modern::Window as its only argument and may return
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
      module ButtonBar
        # Builds a Rubbs::Modern::Widgets::Button for each of +descriptors+, places them
        # on the bottom row of +window+ and adds them to it. A click runs the
        # descriptor's +on_click+ and then closes the window on +app+ unless
        # it returned +:keep+ or +keep_open+ is set.
        #
        # Returns <tt>{ widgets:, primary:, by_key: }</tt>: the buttons in
        # order, the primary button (or +nil+), and a Hash of descriptor key to
        # button.
        def self.attach(window, app, descriptors)
          descriptors = Array(descriptors)
          widgets = descriptors.map { |d| Widgets::Button.new(label: d[:label], on_click: handler(window, app, d)) }
          place(window, widgets, descriptors)
          widgets.each { |w| window.add(w) }
          pairs = descriptors.zip(widgets)
          {
            widgets: widgets,
            primary: pairs.find { |d, _| d[:primary] }&.last,
            by_key:  pairs.select { |d, _| d[:key] }.to_h { |d, w| [d[:key], w] }
          }
        end

        # Positions (or re-positions) the bar's +widgets+, built from
        # +descriptors+, against the window's current bounds: the left ones
        # from the left edge, the right ones flush against the right edge, the
        # centred ones in the middle. Used by ::attach and by window relayouts.
        def self.place(window, widgets, descriptors)
          default = descriptors.length == 1 ? :center : :right
          groups  = widgets.each_index.group_by { |i| descriptors[i][:align] || default }
          %i[left right center].each do |align|
            row = widgets.values_at(*groups.fetch(align, []))
            lay_out(row, start(window.bounds, align, row), window.bounds.y + window.bounds.height - 2)
          end
        end

        # The column the +row+ of buttons aligned +align+ starts at in
        # +bounds+.
        def self.start(bounds, align, row)
          total = [row.sum { |w| width(w) + 1 } - 1, 0].max
          case align
          when :left  then bounds.x + 2
          when :right then bounds.x + bounds.width - 1 - total
          else bounds.x + ((bounds.width - total) / 2)
          end
        end

        # Lays the +row+ of buttons out side by side from column +x+ on row +y+.
        def self.lay_out(row, x, y)
          row.each do |w|
            w.layout(x, y, width(w), 1)
            x += width(w) + 1
          end
        end

        # The width of +button+ on screen, brackets included.
        def self.width(button) = "[ #{button.display_label} ]".length

        # The click handler for +descriptor+: it calls the descriptor's
        # +on_click+ with +window+, closes the window on +app+ unless the
        # result is +:keep+ or +keep_open+ is set, and returns +:handled+.
        def self.handler(window, app, descriptor)
          lambda do |_button|
            result = descriptor[:on_click]&.call(window)
            app.close_window(window) unless descriptor[:keep_open] || result == :keep
            :handled
          end
        end

        private_class_method :start, :lay_out, :width, :handler
      end
    end
  end
end
