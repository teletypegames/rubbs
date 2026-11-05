# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      class Pages
        # How a Rubbs::Common::Screens::Pages runner paints: the screen drawn fresh for every
        # repaint, and only what changed sent, on either face.
        module Painting
          # Where the caller's cursor rests after a repaint, set while drawing:
          # +row+, +col+ in the coordinates of the screen drawn on (1-based on a
          # Rubbs::Modern::FrameBuffer, where the cursor is also shown; 0-based on a
          # Rubbs::Petscii::Canvas). Without it a modern terminal's cursor is
          # hidden and a C64's stays where the last cell left it.
          def cursor(row, col)
            @cursor = [row, col]
          end

          # Draws the screen and sends what changed since the last repaint, or
          # the whole screen with +whole+ (and after #hand_over, or when the
          # terminal changed its size). Nothing while the line is handed over.
          # Returns the bytes written (empty when nothing changed).
          def redraw(whole: false)
            return ''.b if @handed

            petscii? ? paint_petscii(whole) : paint_modern(whole)
          end

          private

          def clear_for_hand_over
            if petscii?
              set = @charset == :lower ? Petscii::Canvas::LOWERCASE : Petscii::Canvas::UPPERCASE
              @session.write_raw([set, Petscii::Canvas::CLEAR].pack('C*'))
            else
              @session.write(MODERN_CLEAR + Modern::Ansi::SHOW_CURSOR)
            end
          end

          def paint_petscii(whole)
            @cursor = nil
            canvas = Petscii::Canvas.new(charset: @charset)
            draw(canvas)
            bytes = whole || @shown.nil? ? canvas.frame : canvas.diff(@shown)
            @shown = canvas
            return bytes if bytes.empty?

            bytes += canvas.cursor(*@cursor) if @cursor
            @session.write_raw(bytes)
            bytes
          end

          def paint_modern(whole)
            @cursor = nil
            frame = Modern::FrameBuffer.new(@session.term_cols, @session.term_rows)
            draw(frame)
            whole ||= @shown.nil? || [@shown.cols, @shown.rows] != [frame.cols, frame.rows]
            body = whole ? MODERN_CLEAR + frame.diff(Modern::FrameBuffer.new(frame.cols, frame.rows)) : frame.diff(@shown)
            @shown = frame
            out = modern_cursor(body, whole)
            @session.write(out) unless out.empty?
            out
          end

          # +body+ with the cursor hidden before it and shown where #cursor put
          # it after it; empty when neither the screen nor the cursor changed.
          def modern_cursor(body, whole)
            return '' if body.empty? && !whole && @cursor == @cursor_at

            out = +''
            out << Modern::Ansi::HIDE_CURSOR if @cursor_shown != false || whole
            out << body
            out << "#{Modern::Ansi::CSI}#{@cursor[0]};#{@cursor[1]}H#{Modern::Ansi::SHOW_CURSOR}" if @cursor
            @cursor_shown = !@cursor.nil?
            @cursor_at = @cursor
            out
          end
        end

        include Painting
      end
    end
  end
end
