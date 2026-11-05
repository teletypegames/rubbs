# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      class Profile
        # How a Rubbs::Common::Auth::Profile draws its head on either face: the look's
        # drawing in the middle, the title, who is on the line, and a row of
        # air for the menu under them.
        module Drawing
          private

          # Who is on the line, a line; and their roles (or a guest's note), a
          # line or none.
          def status
            return [@words[:guest], @look.note].compact unless identity.signed_in?

            [format(@words[:signed_in], name: identity.name), format(@words[:roles], roles: identity.roles.join(', '))]
          end

          def header = petscii? ? petscii_header : modern_header

          def modern_header
            cols  = @session.term_cols.to_i
            lines = [*modern_art(cols), '', *modern_text(cols)]
            crlf = Modern::Ansi::CRLF
            @session.write("#{Modern::Ansi::RESET}#{Modern::Ansi::CLEAR}#{crlf}#{lines.join(crlf)}#{crlf * 2}")
          end

          # The drawing's lines in the middle of +cols+; none when it is wider.
          def modern_art(cols)
            art = @look.modern
            return [] unless art && art.cols <= cols

            art.ansi_lines.map { |line| centred(line, art.cols, cols) }
          end

          # The title and the status in the middle of +cols+, in their colours.
          def modern_text(cols)
            roles = [:title, :text, *([:dim] * (status.size - 1))]
            [@look.title, *status].zip(roles).map do |text, role|
              centred("#{@colors[role]}#{text}#{Modern::Ansi::RESET}", text.length, cols)
            end
          end

          def centred(text, width, cols) = "#{' ' * [(cols - width) / 2, 0].max}#{text}"

          # The same on a C64: drawn on a canvas in one go, the cursor then two
          # rows under the status.
          def petscii_header
            canvas = Petscii::Canvas.new(charset: :lower)
            row = petscii_art(canvas) + 1
            roles = [:title, :text, *([:dim] * (status.size - 1))]
            [@look.title, *status].zip(roles).each { |text, role| row = c64_line(canvas, row, text, role) }
            @session.write_raw(canvas.frame + "\r\r".b)
          end

          # Draws the C64 drawing from row 1 in the middle; the row after it.
          def petscii_art(canvas)
            art = @look.petscii
            return 1 unless art && art.rows <= PETSCII_ROWS

            art.draw_canvas(canvas, row: 1, col: (Petscii::COLS - art.cols) / 2)
            1 + art.rows
          end

          def c64_line(canvas, row, text, role)
            text = text.to_s[0, Petscii::COLS - 1]
            canvas.text(row, (Petscii::COLS - 1 - text.length) / 2, text, @c64.fetch(role))
            row + 1
          end
        end
      end
    end
  end
end
