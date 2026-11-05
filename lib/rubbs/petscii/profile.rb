# frozen_string_literal: true

module Rubbs
  module Petscii
    # The head of a caller's profile (Rubbs::Common::Auth::Profile) on a
    # Commodore 64: drawn on a Canvas in one go (the look's drawing, the
    # title, who is on the line), the cursor then two rows under it for the
    # menu.
    module Profile
      module_function

      # Writes the head of +profile+ on +session+.
      def header(session, profile)
        canvas = Canvas.new(charset: :lower)
        row = art(canvas, profile.look.petscii) + 1
        profile.head_lines.each { |text, role| row = line(canvas, row, text, profile.c64_colors.fetch(role)) }
        session.write_raw(canvas.frame + "\r\r".b)
      end

      # Draws +art+ from row 1 in the middle (when it has at most
      # Rubbs::Common::Auth::Profile::PETSCII_ROWS rows); the row after it.
      def art(canvas, art)
        return 1 unless art && art.rows <= Common::Auth::Profile::PETSCII_ROWS

        Art.draw(art, canvas, row: 1, col: (COLS - art.cols) / 2)
        1 + art.rows
      end

      # +text+ in the middle of +row+ in +color+; the next row.
      def line(canvas, row, text, color)
        text = text.to_s[0, COLS - 1]
        canvas.text(row, (COLS - 1 - text.length) / 2, text, color)
        row + 1
      end
    end
  end
end
