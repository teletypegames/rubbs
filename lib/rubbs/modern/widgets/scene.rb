# frozen_string_literal: true

require_relative 'widget'

module Rubbs
  module Modern
    module Widgets
      # A Rubbs::Common::Art as a picture of the modern face that shows the board's
      # life: the art (with the layers stacked on it) as the background, and
      # over it the hotspots filled from data, each by a block given for it.
      # A block is called at every render with the Art::Hotspot and returns
      # what goes there: a String (ANSI colours allowed; lines split at
      # <tt>\n</tt> fill the hotspot's rows), or +nil+ to leave the art as it
      # is. What a block returns is cut to its hotspot.
      #
      #   house = Rubbs::Common::Art.load('art/house.yml').with(*Rubbs::Common::Season.now.layers)
      #   scene = Rubbs::Modern::Widgets::Scene.new(art: house, align: :center)
      #   scene.fill(:window_1) { node_busy?(1) ? "\e[38;5;220m▓" : nil }
      #   scene.fill(:mailbox)  { |spot| "✉#{unread}".ljust(spot.width) }
      #   container.add(scene)
      #
      # On a terminal smaller than the art the scene is cut to its bounds:
      # what is right of and below them is left off, and a hotspot outside
      # is not filled. With <tt>crop: false</tt> it draws nothing instead (a
      # dashboard that drops the picture on a small screen asks #fits?).
      class Scene < Widget
        # The art drawn: a Rubbs::Common::Art. Setting it keeps the blocks of the
        # hotspots.
        attr_accessor :art
        # Placement of the art in the bounds: +align+ +:left+, +:center+ or
        # +:right+; +valign+ +:top+, +:middle+ or +:bottom+.
        attr_accessor :align, :valign
        # Whether a scene larger than its bounds is cut (true) or not drawn.
        attr_accessor :crop
        # Whether the widget takes its parent's bounds on every render.
        attr_accessor :fill_parent

        # Creates the scene of +art+ (a Rubbs::Common::Art); +fills+ maps hotspot
        # names to blocks, as #fill does; +align+, +valign+, +crop+ and
        # +fill_parent+ as the attributes. Other keywords go to Widget.new.
        # Raises Art::Error for a hotspot name the art does not have.
        def initialize(art:, fills: {}, align: :left, valign: :top, crop: true, fill_parent: false, **kw)
          super(**kw)
          @art         = art
          @align       = align
          @valign      = valign
          @crop        = crop
          @fill_parent = fill_parent
          @fills       = {}
          fills.each { |name, block| fill(name, &block) }
        end

        # Sets the block that fills hotspot +name+ at every render (see the
        # class description). Raises Art::Error for a name the art does not
        # have. Returns +self+.
        def fill(name, &block)
          @art.hotspot(name)
          @fills[name.to_sym] = block
          self
        end

        # Whether the whole art fits in the bounds.
        def fits? = @art.cols <= bounds.width && @art.rows <= bounds.height

        # Draws the art and the filled hotspots into +frame+, a
        # Rubbs::Modern::FrameBuffer, inside the bounds.
        def render(frame)
          @bounds = parent.bounds.dup if @fill_parent && parent&.bounds
          return unless drawable?

          view = self.view
          @art.draw(frame, x: view.x, y: view.y, width: view.width, height: view.height)
          @fills.each do |name, block|
            spot = @art.hotspots[name]
            paint(frame, spot, block.call(spot), view) if spot
          end
        end

        private

        def drawable? = bounds.width.positive? && bounds.height.positive? && (@crop || fits?)

        # Where the art is drawn: a Rect at the screen cell of its top left,
        # as large as the part of it that shows.
        def view = Rect.new(*corner, [@art.cols, bounds.width].min, [@art.rows, bounds.height].min)

        # The screen cell of the art's top left, [x, y].
        def corner
          [bounds.x + shift(bounds.width - @art.cols, @align, :left, :right),
           bounds.y + shift(bounds.height - @art.rows, @valign, :top, :bottom)]
        end

        # The cells the art moves along an axis with +free+ cells to spare,
        # by +align+: none at +start+, all at +finish+, half otherwise.
        def shift(free, align, start, finish)
          free = [free, 0].max
          { start => 0, finish => free }.fetch(align, free / 2)
        end

        # Writes +content+ into +spot+, cut to the spot and to the +view+ of
        # the art.
        def paint(frame, spot, content, view)
          return if content.nil? || spot.col >= view.width

          lines = content.to_s.split("\n").first(rows_shown(spot, view))
          lines.each_with_index { |line, i| paint_line(frame, line, spot, view, i) }
        end

        # Writes +line+ on row +index+ of +spot+, cut to the spot and the view.
        def paint_line(frame, line, spot, view, index)
          frame.move(view.x + spot.col, view.y + spot.row + index)
          frame.write_ansi(FrameBuffer.clip_ansi(line, [spot.width, view.width - spot.col].min))
        end

        # The rows of +spot+ inside the +view+.
        def rows_shown(spot, view) = (view.height - spot.row).clamp(0, spot.height)
      end
    end
  end
end
