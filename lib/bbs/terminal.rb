# frozen_string_literal: true

module BBS
  # The first question of a call on a board with two faces: which one the
  # terminal gets. The board guesses first from the telnet answers: a window
  # wider than 40 columns is a modern terminal; 40 columns, or no answer at
  # all (a C64 behind a WiFi modem talks plain TCP), most likely a Commodore.
  # The question is plain ASCII in capitals, which an ANSI terminal and a C64
  # in either character set print alike, and each line names what goes on the
  # wire: ANSI with xterm's 256 colours and mouse, or PETSCII.
  #
  # A key only picks, RETURN takes it: a line-mode telnet sends the digit and
  # the RETURN together, and a RETURN left on the line would land in the first
  # screen. A changed pick prints the prompt again on a new line, since the
  # two machines go back a character differently. A caller who does not answer
  # gets what is picked, or the guess.
  #
  # A call forwarded by another board's gateway (Telnet::Forwarded, a
  # BBS::Gateway with <tt>forward: true</tt>) had its question there: the
  # face picked there is taken without asking, and without the splash.
  module Terminal
    # Seconds to wait for the telnet negotiation before guessing.
    SETTLE = 1.5
    # Seconds to wait for each key at the question before taking the pick.
    WAIT   = 60

    # The two faces: for each, the digit shown, the label of its line in the
    # question, and the keys that pick it.
    FACES = {
      modern:  { digit: '1', label: 'MODERN (ANSI/XTERM, 256 COLORS)', keys: %w[1 a A m M] },
      petscii: { digit: '2', label: 'COMMODORE 64 (PETSCII, 40 COLUMNS)', keys: %w[2 c C p P] }
    }.freeze

    # Guesses the face of +session+ from the telnet answers: +:modern+ when
    # the terminal reported its window size within SETTLE seconds and it is
    # wider than 40 columns, +:petscii+ otherwise.
    def self.guess(session)
      session.settle(timeout: SETTLE) && session.term_cols > Petscii::COLS ? :modern : :petscii
    end

    # The whole first step as a Flow: ask, switch the line (PETSCII on a C64,
    # mouse reporting on a modern terminal when config.mouse is on), then run
    # that face's Flow. The board keeps config.mouse_on_connect off: the
    # mouse's escape sequence would be garbage on a C64.
    #
    # [title]   the board's name, shown above the question
    # [modern]  the BBS::Flow for a modern terminal
    # [petscii] the BBS::Flow for a PETSCII line, a Commodore 64
    # [splash]  a BBS::Splash to show between the question and the face, or
    #           +nil+ for none
    #
    # A forwarded call (Telnet::Forwarded#forwarded_face) gets neither the
    # question nor the splash.
    #
    # Returns a BBS::Flow that halts when the line drops at the question.
    #
    #   BBS.configure { |c| c.flow = BBS::Terminal.flow(title: 'My board', modern: MODERN, petscii: PETSCII) }
    def self.flow(title:, modern:, petscii:, splash: nil)
      faces = { modern: modern, petscii: petscii }
      Flow.define do
        call do |ctx, runner|
          session   = runner.session
          guess     = Terminal.guess(session)
          forwarded = session.respond_to?(:forwarded_face) && session.forwarded_face
          face      = forwarded || Question.new(session, title, default: guess).ask
          next :halt if face.nil?

          Terminal.switch(session, face)
          next :halt if splash && !forwarded && !splash.continue?(session, face)

          FlowRunner.new(session, ctx[:session_id], faces[face], context: ctx).run
          nil
        end
      end
    end

    # Switches the line of +session+ to +face+: PETSCII on a C64, mouse
    # reporting on a modern terminal when <tt>BBS.config.mouse</tt> is on.
    def self.switch(session, face)
      if face == :petscii
        session.petscii!
      elsif BBS.config.mouse
        session.enable_mouse
      end
    end

    # The question itself, in plain ASCII capitals: the faces, a digit
    # each, and the guess as the default. A key only picks, RETURN takes
    # it; a changed pick prints the prompt again on a new line.
    class Question
      # The keys that take the pick.
      TAKE_KEYS = %i[enter idle].freeze
      # The keys that take the pick back.
      UNPICK_KEYS = %i[backspace ctrl_t].freeze

      # The question of +title+ for +session+, +default+ the face taken when
      # the caller just presses RETURN (Terminal.guess when +nil+).
      def initialize(session, title, default: nil)
        @session = session
        @title   = title
        @default = default || Terminal.guess(session)
        @picked  = nil
      end

      # Asks, and returns +:modern+ or +:petscii+; +nil+ when the line
      # drops.
      def ask
        @session.write question
        loop do
          key = @session.readkey(timeout: WAIT)
          return nil if key.nil?
          break if TAKE_KEYS.include?(key)

          pick(choice(key))
        end
        @session.write @picked ? Ansi::CRLF : "#{FACES[@default][:digit]}#{Ansi::CRLF}"
        @picked || @default
      end

      private

      # Whether +choice+ changes the pick: a face not picked yet, or
      # +:none+ while one is.
      def changes?(choice) = choice && choice != @picked && !(choice == :none && @picked.nil?)

      def prompt = "YOUR TERMINAL [#{FACES[@default][:digit]}]: "

      def question
        faces = FACES.values.map { |f| "#{f[:digit]} - #{f[:label]}#{Ansi::CRLF}" }.join
        "#{Ansi::CRLF * 2}#{@title.upcase}#{Ansi::CRLF * 2}#{faces}#{Ansi::CRLF}#{prompt}"
      end

      # The face +key+ picks, +:none+ for a key that takes the pick back,
      # +nil+ for any other.
      def choice(key)
        FACES.find { |_, f| f[:keys].include?(key) }&.first || (:none if UNPICK_KEYS.include?(key))
      end

      def pick(choice)
        return unless changes?(choice)

        @session.write "#{Ansi::CRLF}#{prompt}" if @picked
        @picked = choice == :none ? nil : choice
        @session.write FACES[@picked][:digit] if @picked
      end
    end
  end
end
