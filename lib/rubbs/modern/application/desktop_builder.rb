# frozen_string_literal: true

require_relative '../widgets/desktop'

module Rubbs
  module Modern
    class Application
      # The desktop of an Application (Builder#desktop): what lies under the
      # windows, placed by words instead of coordinates, and placed again when
      # the screen changes size.
      #
      #   desktop do
      #     art     Logo::HALF_BLOCKS, top: 2
      #     line    TAGLINE, bottom: 1
      #     line(top: 3, align: :right, margin: 2) { "#{feeds.size} FEEDS" }
      #     widget(height: Pharos::HEIGHT, middle: -10) { Pharos.new }
      #     button('Master', bottom: 0, align: :right) { master }
      #     on_show { search }
      #   end
      #
      # Where each goes, in rows of the desktop: +top: n+ (from the top),
      # +bottom: n+ (from the bottom), +middle: n+ (from the middle, negative
      # above); across: +align+ +:center+ (default), +:left+ or +:right+, with
      # +margin+ columns from that edge. A block for the text is evaluated in
      # the application at every repaint.
      class DesktopBuilder
        # The items declared, Rubbs::Modern::Widgets::Desktop::Item each.
        attr_reader :items

        # Evaluates the declarations of the block.
        def initialize(&block)
          @items   = []
          @on_show = nil
          instance_eval(&block) if block
        end

        # Lines drawn as one block (a logo), in the +style+ role (default
        # +:accent+).
        def art(lines, style: :accent, **place)
          @items << Widgets::Desktop::Item.new(kind: :art, content: Array(lines), style: style, place: place)
        end

        # One line of text (or a block giving it), in the +style+ role
        # (default +:text_dim+).
        def line(text = nil, style: :text_dim, **place, &block)
          @items << Widgets::Desktop::Item.new(kind: :line, content: block || text, style: style, place: place)
        end

        # A Rubbs::Modern::Widgets::Widget of the board, made by the block for each call (in the
        # application), the desktop's width (or +width+) and +height+ rows, or
        # the whole desktop with <tt>fill: true</tt>. A widget with a +tick+
        # method is ticked once a second.
        def widget(height: 1, **place, &make)
          @items << Widgets::Desktop::Item.new(
            kind:    :widget,
            content: make,
            style:   nil,
            place:   place.merge(height: height)
          )
        end

        # A button that runs the block in the application.
        def button(label, **place, &action)
          @items << Widgets::Desktop::Item.new(kind: :button, content: [label, action], style: nil, place: place)
        end

        # The block run in the application once the desktop is up: the first
        # window or dialog.
        def on_show(&block) = (@on_show = block)

        # Adds the desktop to +app+.
        def install(app)
          app.desktop = app.add(Widgets::Desktop.new(app, @items))
        end

        # Runs the #on_show block in +app+.
        def show(app)
          app.instance_exec(&@on_show) if @on_show
        end
      end
    end
  end
end
