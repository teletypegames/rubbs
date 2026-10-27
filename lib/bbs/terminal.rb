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
  module Terminal
    SETTLE = 1.5
    WAIT   = 60

    FACES = {
      modern: { digit: '1', label: 'MODERN (ANSI/XTERM, 256 COLORS)', keys: %w[1 a A m M] },
      c64:    { digit: '2', label: 'COMMODORE 64 (PETSCII, 40 COLUMNS)', keys: %w[2 c C p P] }
    }.freeze

    def self.guess(session)
      session.settle(timeout: SETTLE) && session.term_cols > Petscii::COLS ? :modern : :c64
    end

    # :modern or :c64; nil when the line drops.
    def self.choose(session, title:)
      default = guess(session)
      prompt  = "YOUR TERMINAL [#{FACES[default][:digit]}]: "
      session.write "\r\n\r\n#{title.upcase}\r\n\r\n" \
                    "#{FACES.values.map { |f| "#{f[:digit]} - #{f[:label]}\r\n" }.join}\r\n#{prompt}"
      picked = nil
      loop do
        key = session.readkey(timeout: WAIT)
        return nil if key.nil?
        break if %i[enter idle].include?(key)

        choice = FACES.find { |_, f| f[:keys].include?(key) }&.first
        choice = :none if choice.nil? && %i[backspace ctrl_t].include?(key)
        next if choice.nil? || (choice == :none && picked.nil?) || choice == picked

        session.write "\r\n#{prompt}" unless picked.nil?
        picked = choice == :none ? nil : choice
        session.write FACES[picked][:digit] if picked
      end
      session.write picked ? "\r\n" : "#{FACES[default][:digit]}\r\n"
      picked || default
    end

    # The whole first step as a Flow: ask, switch the line (PETSCII on a C64,
    # mouse reporting on a modern terminal), then run that face's Flow. The
    # board keeps config.mouse_on_connect off: the mouse's escape sequence
    # would be garbage on a C64.
    def self.flow(title:, modern:, c64:)
      faces = { modern: modern, c64: c64 }
      Flow.define do
        call do |ctx, runner|
          face = Terminal.choose(runner.session, title: title)
          next :halt if face.nil?

          face == :c64 ? runner.session.petscii! : runner.session.enable_mouse
          FlowRunner.new(runner.session, ctx[:session_id], faces[face], context: ctx).run
          nil
        end
      end
    end
  end
end
