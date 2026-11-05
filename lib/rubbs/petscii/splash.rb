# frozen_string_literal: true

module Rubbs
  module Petscii
    # The splash (Rubbs::Common::Call::Splash) on a Commodore 64: its
    # +petscii-upper+ drawing at the top in the middle of a Canvas, the prompt
    # (or the choices) on the last row; the lowercase set and a clear screen
    # when the caller goes on, as Rubbs::Common::Line::Telnet#petscii! left
    # them.
    class Splash
      # The painter of +splash+, a Rubbs::Common::Call::Splash.
      def initialize(splash)
        @splash = splash
      end

      # Whether the drawing fits the screen: always (a C64 has 40×25).
      def fits?(_session) = true

      # Shows the splash on +session+, the choices when +asks+.
      def show(session, asks)
        art    = @splash.petscii
        canvas = Art.draw(art, Canvas.new, col: (COLS - art.cols) / 2)
        if asks
          choices(canvas)
        else
          canvas.text(ROWS - 1, (COLS - @splash.prompt.size) / 2, @splash.prompt, :light_grey)
        end
        session.write_raw(canvas.frame)
      end

      # After the wait (whatever +key+ came): the lowercase set and a clear
      # screen.
      def leave(session, _key)
        session.write_raw(Petscii.bytes("#{LOWERCASE}#{CLEAR}"))
      end

      private

      # The choices in capitals (the drawing's character set has no small
      # letters, and no |: a line glyph stands for it), each key in its
      # colour.
      def choices(canvas)
        col = (COLS - @splash.choice_width) / 2
        @splash.choice_runs.each do |text, role|
          canvas.text(ROWS - 1, col, text.upcase.tr('|', '│'), @splash.colors[:"c64_#{role}"])
          col += text.length
        end
      end
    end
  end
end
