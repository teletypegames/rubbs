# frozen_string_literal: true

module Rubbs
  module Modern
    module Widgets
      # A single line of text. The text may carry ANSI colour codes.
      class Label < Widget
        # [text]      the text shown (anything; +to_s+ is called on it)
        # [align]     +:left+, +:center+ or +:right+ within the bounds
        # [style_key] the theme role the text is drawn in
        attr_accessor :text, :align, :style_key

        # Creates a label with +text+, +align+ (default +:left+) and
        # +style_key+ (default +:text+).
        def initialize(text: '', align: :left, style_key: :text, **kw)
          super(**kw)
          @text       = text
          @align      = align
          @style_key  = style_key
        end

        # Draws the text on the first row of the bounds into +frame+, a
        # Rubbs::Modern::FrameBuffer, cut to the width and aligned; its ANSI escape
        # sequences take no width.
        def render(frame)
          return if bounds.width <= 0

          clipped = FrameBuffer.clip_ansi(@text.to_s, bounds.width)
          frame.move(bounds.x + offset(FrameBuffer.visible_width(clipped)), bounds.y)
          frame.write_ansi(clipped, base_sgr: style(@style_key))
        end

        private

        # The columns before a text +length+ long, by the alignment.
        def offset(length)
          case @align
          when :center then [bounds.width - length, 0].max / 2
          when :right  then bounds.width - length
          else 0
          end
        end
      end
    end
  end
end
