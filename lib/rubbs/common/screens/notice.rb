# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      # A notice shown over a page until a key (Rubbs::Common::Screens::Pages
      # shows what Rubbs::Common::Line::Session#announce tells this way: a badge
      # earned, the server's shutdown): a box in the middle of the screen, the
      # words wrapped in it, on either face.
      class Notice < Page
        # The most columns the words take on a modern terminal.
        WIDTH = 56
        # The words under the box.
        PRESS = 'Press a key'

        # The words of the notice.
        attr_reader :text

        # A notice of +text+ titled +title+.
        def initialize(text, title: 'Notice')
          super()
          @text  = text.to_s
          @title = title.to_s
        end

        # The hint bar of a C64 frame around it (Rubbs::Petscii::Kit::Frame).
        def hint = [[PRESS, false]]

        # No section of a frame is lit under it.
        def section = nil

        # Draws the box on +screen+: a Rubbs::Petscii::Canvas on a C64, a
        # Rubbs::Modern::FrameBuffer on a modern terminal.
        def draw(screen) = pages.petscii? ? draw_petscii(screen) : draw_modern(screen)

        private

        def draw_modern(frame)
          width = (frame.cols - 8).clamp(20, WIDTH)
          box   = modern_box(wrapped(width), width)
          top   = [(frame.rows - box.size - 1) / 2, 1].max
          left  = [(frame.cols - width - 4) / 2, 1].max + 1
          print_lines(frame, [*box.map { |l| "\e[1;33m#{l}\e[0m" }, "  \e[2m#{PRESS}\e[0m"], x: left, y: top)
        end

        def wrapped(width) = Modern::FrameBuffer.wrap_ansi(Text.clean(@text, keep_newlines: false), width)

        def modern_box(lines, width)
          ["┌─ #{@title} #{'─' * [width - @title.length - 1, 0].max}┐", *lines.map { |l| "│ #{l.ljust(width)} │" },
           "└#{'─' * (width + 2)}┘"]
        end

        def draw_petscii(canvas)
          cols  = Petscii::COLS - 4
          lines = Modern::FrameBuffer.wrap_ansi(Petscii::Canvas.plain(@text, pages.charset), cols - 2).first(8)
          rows  = [[" #{@title} ", Petscii::Canvas::YELLOW], *lines.map { |l| [" #{l}", Petscii::Canvas::WHITE] },
                   [" #{PRESS}", Petscii::Canvas::GREY]]
          top = [(Petscii::ROWS - rows.size) / 2, 2].max
          rows.each_with_index { |(text, color), i| canvas.text(top + i, 2, text.ljust(cols), color, rvs: true) }
        end
      end
    end
  end
end
