# frozen_string_literal: true

module Rubbs
  module Modern
    # The splash (Rubbs::Common::Call::Splash) on a modern terminal: its
    # drawing and the prompt (or the choices) in the middle of the window, the
    # cursor hidden; a clear screen when the caller goes on.
    class Splash
      # The painter of +splash+, a Rubbs::Common::Call::Splash.
      def initialize(splash)
        @splash = splash
      end

      # Whether the drawing fits the terminal of +session+ (a narrower one
      # gets no splash).
      def fits?(session) = session.term_cols >= @splash.modern.cols

      # Shows the splash on +session+, the choices when +asks+.
      def show(session, asks)
        art   = @splash.modern
        top   = [(session.term_rows.to_i - art.rows - 1) / 2, 0].max
        lines = Art.lines(art).map { |line| centred(session, art.cols, line) }
        lines << (asks ? choices(session) : prompt(session))
        session.write("#{Ansi::HIDE_CURSOR}#{Ansi::CLEAR}#{Ansi::CRLF * top}#{lines.join(Ansi::CRLF)}")
      end

      # After the wait: the cursor back and a clear screen, when a +key+ came
      # (+nil+: the line dropped).
      def leave(session, key)
        session.write("#{Ansi::SHOW_CURSOR}#{Ansi::CLEAR}") if key
      end

      private

      def prompt(session) = centred(session, @splash.prompt.size, "#{Ansi::GREY}#{@splash.prompt}#{Ansi::RESET}")

      def choices(session)
        text = @splash.choice_runs.map { |part, role| "#{@splash.colors[role]}#{part}" }.join
        centred(session, @splash.choice_width, "#{text}#{Ansi::RESET}")
      end

      def centred(session, width, text) = "#{' ' * ((session.term_cols - width) / 2)}#{text}"
    end
  end
end
