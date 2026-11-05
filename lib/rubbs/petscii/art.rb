# frozen_string_literal: true

module Rubbs
  module Petscii
    # A +petscii-upper+ drawing (Rubbs::Common::Art) on a Commodore 64: on a
    # Canvas, or as the raw PETSCII of a whole screen.
    #
    #   Rubbs::Petscii::Art.draw(art, canvas, row: 2, col: 9)
    #   session.write_raw(Rubbs::Petscii::Art.bytes(art))
    module Art
      module_function

      # Draws +art+ on +canvas+, a Canvas, with its top left at +row+, +col+
      # (0-based); cells off the screen are cut. A visible cell with no
      # colour is light grey, the C64's text colour. Raises ArgumentError for
      # a cp437 art.
      #
      # Returns +canvas+.
      def draw(art, canvas, row: 0, col: 0)
        raise ArgumentError, "#{art.path}: a #{art.charset} art does not go on a C64 canvas" unless art.petscii?

        art.grid.each_with_index do |cells, r|
          cells.each_with_index do |cell, c|
            code, reversed = Canvas.code(cell.char)
            color = cell.fg ? cell.fg.c64 : Canvas::LIGHT_GREY
            canvas.put(row + r, col + c, code, color, rvs: cell.rvs ^ reversed)
          end
        end
        canvas
      end

      # A new Canvas with +art+ drawn at its top left.
      def canvas(art) = draw(art, Canvas.new)

      # The raw PETSCII of the whole screen with +art+ on it (the #canvas's
      # +frame+), a binary String to send with <tt>session.write_raw</tt>.
      def bytes(art) = canvas(art).frame
    end
  end
end
