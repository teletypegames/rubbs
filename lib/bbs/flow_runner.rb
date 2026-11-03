# frozen_string_literal: true

module BBS
  # Runs a BBS::Flow on a session: each step in order (see
  # BBS::Flow::Steps), writing to and reading from the caller's line, with
  # a context Hash that +ask+ steps fill and later steps and blocks read.
  #
  #   BBS::FlowRunner.new(session, session_id, flow, context: { name: 'Zsolt' }).run
  #
  # An error raised in a +call+ block is reported to the caller and on
  # stderr and the flow carries on; a dropped line (IOError, EPIPE,
  # ECONNRESET) ends it.
  class FlowRunner
    # The colour of each +style+ of a step, from the one ANSI palette
    # (BBS::Ansi). An unknown style is +:muted+.
    STYLES = {
      success: Ansi::BRIGHT_GREEN,
      muted:   Ansi::GREY,
      error:   Ansi::BRIGHT_RED,
      info:    Ansi::YELLOW,
      prompt:  Ansi::WHITE
    }.freeze
    # The results of a step that end the steps being run.
    STOPS = %i[halt exit_menu].freeze
    # The width of a menu: it fits a C64's 40 columns.
    MENU_WIDTH = 38

    # The caller's session ID, the BBS::Session the flow runs on, and the
    # context Hash the steps share.
    attr_reader :session_id, :session, :context

    # Creates a runner for +flow+ (a BBS::Flow) on +session+. +context+ is
    # the Hash its steps share (the caller's, so a nested flow and its face
    # see the same one; a door passes a copy); +session_id+ is stored in it
    # under +:session_id+.
    def initialize(session, session_id, flow, context: {})
      @session    = session
      @session_id = session_id
      @flow       = flow
      @context    = context
      @context[:session_id] = session_id
    end

    # Runs the flow's steps until they end or one stops the flow. Returns
    # +:halt+ when the flow was stopped (a hang-up, a failed +ask+ or +gate+,
    # a refused confirmation, a block returning +:halt+), +:exit_menu+ when
    # an +exit_menu+ step ran outside a menu, +nil+ otherwise.
    def run = execute(@flow.steps)

    # Runs +steps+ in order until one returns a STOPS result, which is
    # returned; +nil+ when they all ran.
    def execute(steps)
      steps.each do |step|
        result = step.run(self)
        return result if STOPS.include?(result)
      end
      nil
    end

    # Writes +data+ to the caller's line. Blocks of +call+ steps get the
    # runner as their second argument to write with.
    def write(data) = @session.write(data)

    # Reads a line from the caller, echoing +mask+ in place of each
    # character when given. Returns the line, or +nil+ when the caller hung
    # up.
    def readline(mask: nil) = @session.readline(mask: mask)

    # Writes +prompt+ and reads the answer, stripped: in a BBS::Field on a
    # PETSCII line, which edits with the cursor keys, a plain line
    # otherwise. Returns +nil+ when the caller hangs up.
    def ask(prompt)
      return Field.ask(@session, prompt, max: Telnet::MAX_LINE).to_s.strip if petscii?

      write prompt
      readline&.strip
    rescue IOError
      nil
    end

    # A numbered BBS::Selector of +options+, pairs of label and value,
    # with +hint+ on its status row. Returns the value taken, or +nil+ for
    # RUN/STOP, ← or Esc.
    def select(options, hint: nil)
      write Ansi::CRLF
      items = options.map { |label, value| Selector.item(label, value: value) }
      Selector.new(@session, items, width: MENU_WIDTH, numbers: true, hint: hint).run
    end

    # Writes +text+ as one line indented by two spaces, in the colour of
    # +style+.
    def line(text, style: :muted) = write("  #{color(style)}#{text}#{Ansi::RESET}#{Ansi::CRLF}")

    # The SGR sequence of +style+ (a STYLES key; an unknown one is
    # +:muted+).
    def color(style) = STYLES.fetch(style, STYLES[:muted])

    # The folder of the flow's ERB screens: its own, or
    # <tt>BBS.config.screens_dir</tt>.
    def screens_dir = @flow.screens_dir || BBS.config.screens_dir

    private

    def petscii? = @session.respond_to?(:petscii?) && @session.petscii?
  end
end
