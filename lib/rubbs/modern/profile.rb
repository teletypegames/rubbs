# frozen_string_literal: true

module Rubbs
  module Modern
    # The head of a caller's profile (Rubbs::Common::Auth::Profile) on a
    # modern terminal: the look's drawing in the middle, the title, who is on
    # the line, and a row of air for the menu under them.
    module Profile
      module_function

      # Clears the screen of +session+ and writes the head of +profile+.
      def header(session, profile)
        cols  = session.term_cols.to_i
        lines = [*art(profile.look.modern, cols), '', *text(profile, cols)]
        session.write("#{Ansi::RESET}#{Ansi::CLEAR}#{Ansi::CRLF}#{lines.join(Ansi::CRLF)}#{Ansi::CRLF * 2}")
      end

      # The lines of +art+ in the middle of +cols+; none without one or when
      # it is wider.
      def art(art, cols)
        return [] unless art && art.cols <= cols

        Art.lines(art).map { |line| centred(line, art.cols, cols) }
      end

      # The head's lines in the middle of +cols+, in their colours.
      def text(profile, cols)
        profile.head_lines.map do |line, role|
          centred("#{profile.colors[role]}#{line}#{Ansi::RESET}", line.length, cols)
        end
      end

      # +text+ (+width+ columns) in the middle of +cols+.
      def centred(text, width, cols) = "#{' ' * [(cols - width) / 2, 0].max}#{text}"
    end
  end
end
