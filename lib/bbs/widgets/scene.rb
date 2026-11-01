# frozen_string_literal: true

require_relative '../widget'

module BBS
  module Widgets
    # A BBS::Art as a picture of the modern face that shows the board's
    # life: the art (with the layers stacked on it) as the background, and
    # over it the hotspots filled from data, each by a block given for it.
    # A block is called at every render with the Art::Hotspot and returns
    # what goes there: a String (ANSI colours allowed; lines split at
    # <tt>\n</tt> fill the hotspot's rows), or +nil+ to leave the art as it
    # is. What a block returns is cut to its hotspot.
    #
    #   house = BBS::Art.load('art/house.yml').with(*BBS::Season.now.layers)
    #   scene = BBS::Widgets::Scene.new(art: house, align: :center)
    #   scene.fill(:window_1) { node_busy?(1) ? "\e[38;5;220m▓" : nil }
    #   scene.fill(:mailbox)  { |spot| "✉#{unread}".ljust(spot.width) }
    #   container.add(scene)
    #
    # On a terminal smaller than the art the scene is cut to its bounds:
    # what is right of and below them is left off, and a hotspot outside
    # is not filled. With <tt>crop: false</tt> it draws nothing instead (a
    # dashboard that drops the picture on a small screen asks #fits?).
    class Scene < Widget
      # The art drawn: a BBS::Art. Setting it keeps the blocks of the
      # hotspots.
      attr_accessor :art
      # Placement of the art in the bounds: +align+ +:left+, +:center+ or
      # +:right+; +valign+ +:top+, +:middle+ or +:bottom+.
      attr_accessor :align, :valign
      # Whether a scene larger than its bounds is cut (true) or not drawn.
      attr_accessor :crop
      # Whether the widget takes its parent's bounds on every render.
      attr_accessor :fill_parent

      # Creates the scene of +art+ (a BBS::Art); +fills+ maps hotspot
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
      # BBS::FrameBuffer, inside the bounds.
      def render(frame)
        @bounds = parent.bounds.dup if @fill_parent && parent&.bounds
        return if bounds.width <= 0 || bounds.height <= 0
        return if !@crop && !fits?

        x, y = origin
        width  = [@art.cols, bounds.width].min
        height = [@art.rows, bounds.height].min
        @art.draw(frame, x: x, y: y, width: width, height: height)
        @fills.each do |name, block|
          spot = @art.hotspots[name]
          paint(frame, spot, block.call(spot), x, y, width, height) if spot
        end
      end

      private

      # The screen cell of the art's top left.
      def origin
        free_x = [bounds.width - @art.cols, 0].max
        free_y = [bounds.height - @art.rows, 0].max
        dx = { left: 0, right: free_x }.fetch(@align, free_x / 2)
        dy = { top: 0, bottom: free_y }.fetch(@valign, free_y / 2)
        [bounds.x + dx, bounds.y + dy]
      end

      # Writes +content+ into +spot+, cut to the spot and to the visible
      # +width+ × +height+ of the art drawn at +x+, +y+.
      def paint(frame, spot, content, x, y, width, height)
        return if content.nil?

        content.to_s.split("\n").first(spot.height).each_with_index do |line, i|
          row = spot.row + i
          next if row >= height || spot.col >= width

          room = [spot.width, width - spot.col].min
          frame.move(x + spot.col, y + row)
          frame.write_ansi(FrameBuffer.clip_ansi(line, room))
        end
      end
    end
  end
end
