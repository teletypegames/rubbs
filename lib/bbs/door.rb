# frozen_string_literal: true

require_relative 'fake_os'

module BBS
  # A door: a program the caller steps into from the BBS, as in the doors of
  # the old boards. The BBS hands the telnet line over, the program talks to
  # the caller directly, and the line comes back when the program exits.
  #
  # The program is a BBS::FakeOS definition, a BBS::Flow, or anything that
  # responds to <tt>call(session, context)</tt>. A flow gets a copy of the
  # caller's context (so its +ask+ steps cannot overwrite the BBS's own keys), and
  # since a flow ends without an exit command of its own, the door waits for
  # ENTER before handing the line back:
  #
  #   SERMO = BBS::Door.new(:sermo, Sermo::OS, label: '&SERMO')
  #   SERMO.run(session, ctx)
  #
  # Inside an Application, declare doors with the +door+ DSL and let
  # BBS::Application::Builder#run take the caller through them (see
  # BBS::Application).
  class Door
    # The door's name as a Symbol, its menu label, and the program it runs.
    attr_reader :name, :label, :program
    # A line about the door, shown on the statusbar while its menu entry is
    # highlighted, or +nil+.
    attr_reader :hint

    # Creates a door.
    #
    # [name]    the door's name, stored as a Symbol
    # [program] a BBS::FakeOS::Definition, a BBS::Flow, or an object that
    #           responds to <tt>call(session, context)</tt>
    # [label]   the text shown in menus; defaults to +name+ in capitals
    # [hint]    a line about the door for the statusbar, or +nil+
    #
    # Raises ArgumentError when +program+ is none of the three.
    def initialize(name, program, label: nil, hint: nil)
      raise ArgumentError, "Door #{name.inspect}: not a FakeOS definition or a callable" unless
        program.is_a?(FakeOS::Definition) || program.is_a?(Flow) || program.respond_to?(:call)

      @name    = name.to_sym
      @program = program
      @label   = label || name.to_s.upcase
      @hint    = hint
    end

    # Hands the line to the program on a clean screen without mouse
    # reporting, and takes it back when the program returns.
    #
    # [session] the caller's BBS::Session
    # [context] the caller's context Hash; a Flow program gets a copy
    #
    # An error raised by the program is logged to stderr and swallowed, so
    # the caller lands back on the board; IOError and SystemCallError (the
    # line dropped) are re-raised. Mouse reporting is switched back on
    # afterwards when <tt>BBS.config.mouse</tt> is set.
    def run(session, context = {})
      session.disable_mouse
      session.write("\e[0m\e[2J\e[H")
      case @program
      when FakeOS::Definition
        FakeOS::Runner.new(session, @program, context: context).run
      when Flow
        run_flow(session, context)
      else
        @program.call(session, context)
      end
    rescue IOError, SystemCallError
      raise
    rescue StandardError => e
      # A door's fault must not end the caller's call: back to the board.
      warn "BBS door #{@name}: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
    ensure
      (session.enable_mouse if BBS.config.mouse) rescue nil
    end

    private

    def run_flow(session, context)
      FlowRunner.new(session, context[:session_id], @program, context: context.dup).run
      session.write("\e[0m\r\n  \e[0;37mPress ENTER to return to the BBS...\e[0m")
      session.readline
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    end
  end
end
