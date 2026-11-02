# frozen_string_literal: true

module BBS
  class Editor
    # What the editor draws round the text: the reversed title bar with the
    # count of characters, and the bottom row with the key hints or the
    # save-or-quit question. Each method returns the bytes to write,
    # moving a BBS::Cursor.
    class Chrome
      # Draws for +cursor+ (a BBS::Cursor) on a screen +cols+ × +rows+.
      #
      # [title]       the text of the title bar
      # [single_line] whether RETURN saves, which the hints tell
      # [max]         the most characters the text may hold, or +nil+ for
      #               no count
      def initialize(cursor, title:, single_line:, max:, cols:, rows:)
        @cursor = cursor
        @title  = title
        @single = single_line
        @max    = max
        @cols   = cols
        @rows   = rows
        @count  = nil
      end

      # The title bar, written at the cursor (the top left).
      def title = reversed(@title)

      # The bottom row with the key hints.
      def hints
        menu = @cursor.petscii? ? 'STOP/←' : 'Esc'
        bottom(@single ? "#{enter_key} save  #{menu} quit" : "#{menu}: save or quit")
      end

      # The bottom row asking whether to save or quit.
      def question = bottom("S save  Q quit  #{enter_key} back")

      # The count of +length+ characters at the right of the title bar,
      # when there is a limit; empty when there is none or it shows already.
      def count(length)
        return '' unless @max

        count = "#{length}/#{@max} ".rjust("#{@max}/#{@max} ".length)
        return '' if count == @count

        @count = count
        out = @cursor.move(1, @cols - 1 - count.length)
        @cursor.wrote(count.length + 1)
        "#{out}#{Ansi::REVERSE} #{count}#{Ansi::REVERSE_OFF}"
      end

      private

      def enter_key = @cursor.petscii? ? 'RETURN' : 'Enter'

      # The bottom row in reverse, written over with +text+.
      def bottom(text) = @cursor.move(@rows - 1, 1) << reversed(text)

      # +text+ as a reversed bar across the screen but its last column.
      def reversed(text)
        @cursor.wrote(@cols - 1)
        "#{Ansi::REVERSE}#{" #{text}"[0, @cols - 1].ljust(@cols - 1)}#{Ansi::REVERSE_OFF}"
      end
    end
  end
end
