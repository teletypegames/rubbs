# frozen_string_literal: true

module Rubbs
  module Modern
    # The splash (Rubbs::Common::Call::Splash) on a modern terminal: its
    # drawing and the prompt (or the choices and the hint under them) in the
    # middle of the window, the cursor hidden; a clear screen when the caller
    # goes on.
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
        under = under(session, asks)
        top   = [(session.term_rows.to_i - art.rows - under.size) / 2, 0].max
        lines = Art.lines(art).map { |line| centred(session, art.cols, line) } + under
        session.write("#{Ansi::HIDE_CURSOR}#{Ansi::CLEAR}#{Ansi::CRLF * top}#{lines.join(Ansi::CRLF)}")
      end

      # After the wait: the cursor back and a clear screen, when a +key+ came
      # (+nil+: the line dropped).
      def leave(session, key)
        session.write("#{Ansi::SHOW_CURSOR}#{Ansi::CLEAR}") if key
      end

      private

      # The lines under the drawing: the choices and the hint, or the prompt.
      def under(session, asks) = asks ? [choices(session), *hint(session)] : [prompt(session)]

      def prompt(session) = grey(session, @splash.prompt)

      def hint(session) = @splash.hint && grey(session, @splash.hint)

      def grey(session, text) = centred(session, text.size, "#{Ansi::GREY}#{text}#{Ansi::RESET}")

      def choices(session)
        text = @splash.choice_runs.map { |part, role| "#{@splash.colors[role]}#{part}" }.join
        centred(session, @splash.choice_width, "#{text}#{Ansi::RESET}")
      end

      def centred(session, width, text) = "#{' ' * ((session.term_cols - width) / 2)}#{text}"
    end
  end
end
