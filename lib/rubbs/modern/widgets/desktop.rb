# frozen_string_literal: true

require_relative 'container'
require_relative 'label'
require_relative 'button'

module Rubbs
  module Modern
    module Widgets
      # The desktop of an Application, declared with
      # Rubbs::Modern::Application::DesktopBuilder: art, lines, widgets and buttons,
      # each placed by words (+top+, +bottom+, +middle+, +align+, +margin+)
      # within the desktop, and placed again whenever the desktop's size
      # changes.
      class Desktop < Container
        # One declared item: its +kind+ (+:art+, +:line+, +:widget+,
        # +:button+), its +content+, its +style+ role and its +place+ Hash.
        Item = Struct.new(:kind, :content, :style, :place, keyword_init: true)

        # The desktop of +app+ with +items+.
        def initialize(app, items)
          super()
          @app    = app
          @placed = items.map { |item| [item, widgets_of(item)] }
          @placed.map(&:last).flatten.each { |w| add(w) }
        end

        # Ticks the widgets that have a +tick+ method (an animation).
        def tick
          @placed.map(&:last).flatten.each { |w| w.tick if w.respond_to?(:tick) }
        end

        # The board's widget made for the item declared +index+-th of its
        # kind +:widget+, or +nil+.
        def widget(index = 0) = @placed.select { |item, _| item.kind == :widget }[index]&.last&.first

        # Places the items when the desktop's size has changed, refreshes the
        # text of the block lines, and draws them.
        def render(frame)
          area = parent&.bounds || bounds
          place_all(area) unless @area == area.to_a
          refresh_lines
          super
        end

        private

        def widgets_of(item)
          case item.kind
          when :art    then item.content.map { |l| Label.new(text: l, style_key: item.style) }
          when :line   then [Label.new(text: text_of(item), style_key: item.style)]
          when :widget then [@app.instance_exec(&item.content)]
          else
            label, action = item.content
            [Button.new(label: label, on_click: ->(_b) { @app.instance_exec(&action) if action; :handled })]
          end
        end

        def text_of(item) = item.content.is_a?(Proc) ? @app.instance_exec(&item.content).to_s : item.content.to_s

        def refresh_lines
          @placed.each do |item, widgets|
            next unless item.kind == :line && item.content.is_a?(Proc)

            widgets.first.text = text_of(item)
            place_item(item, widgets, @area_rect) if @area_rect
          end
        end

        def place_all(area)
          @area      = area.to_a
          @area_rect = area
          @placed.each { |item, widgets| place_item(item, widgets, area) }
        end

        def place_item(item, widgets, area)
          return widgets.first.layout(area.x, area.y, area.width, area.height) if item.place[:fill]

          width = item_width(item, widgets, area)
          y     = row(item.place, area, item.kind == :widget ? height_of(item) : widgets.size)
          x     = column(item.place, area, width)
          lay_out(item, widgets, x, y, width)
        end

        def lay_out(item, widgets, x, y, width)
          widgets.each_with_index { |w, i| w.layout(x, y + i, item.kind == :art ? w.text.length : width, height_of(item)) }
        end

        def height_of(item) = item.kind == :widget ? item.place.fetch(:height, 1) : 1

        def item_width(item, widgets, area)
          case item.kind
          when :widget then item.place.fetch(:width, area.width)
          when :button then "[ #{widgets.first.display_label} ]".length
          else [widgets.map { |w| FrameBuffer.visible_width(w.text) }.max || 0, area.width].min
          end
        end

        def row(place, area, height)
          top = if place.key?(:top) then place[:top]
                elsif place.key?(:bottom) then area.height - height - place[:bottom]
                else (area.height / 2) + place.fetch(:middle, 0)
                end
          area.y + top.clamp(0, [area.height - 1, 0].max)
        end

        def column(place, area, width)
          margin = place.fetch(:margin, 0)
          case place.fetch(:align, :center)
          when :left  then area.x + margin
          when :right then area.x + area.width - margin - width
          else area.x + ((area.width - width) / 2)
          end
        end
      end
    end
  end
end
