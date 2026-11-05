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

    # A longer text about the door for a list of doors, or +nil+; the program
    # a PETSCII line gets instead of +program+, or +nil+ for the same one.
    attr_reader :about, :petscii

    # Creates a door.
    #
    # [name]    the door's name, stored as a Symbol
    # [program] a BBS::FakeOS::Definition, a BBS::Flow, or an object that
    #           responds to <tt>call(session, context)</tt>
    # [label]   the text shown in menus; defaults to +name+ in capitals
    # [hint]    a line about the door for the statusbar, or +nil+
    #
    # Raises ArgumentError when +program+ is none of the three.
    def initialize(name, program, label: nil, hint: nil, about: nil, petscii: nil)
      raise ArgumentError, "Door #{name.inspect}: not a FakeOS definition or a callable" unless
        program.is_a?(FakeOS::Definition) || program.is_a?(Flow) || program.respond_to?(:call)

      @name    = name.to_sym
      @program = program
      @label   = label || name.to_s.upcase
      @hint    = hint
      @about   = about
      @petscii = petscii
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
    #
    # A door whose program is not a BBS::Gateway (which writes its own)
    # writes a +door crossed+ line when the program returns: the +door+'s
    # name, the +seconds+ in it and the +result+ (+ok+, or +failed+ for an
    # error of the program). A line that drops in the door writes none; its
    # +call ended+ line follows.
    def run(session, context = {})
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result  = 'ok'
      session.disable_mouse
      session.write("#{Ansi::RESET}#{Ansi::CLEAR}")
      start(session, context)
    rescue IOError, SystemCallError
      result = nil
      raise
    rescue StandardError => e
      result = 'failed'
      BBS.log("door #{@name}", e)
    ensure
      (session.enable_mouse if BBS.config.mouse) rescue nil
      crossed(session, started, result) if result
    end

    private

    def program_for(session) = session.respond_to?(:petscii?) && session.petscii? && @petscii ? @petscii : @program

    def crossed(session, started, result)
      return if program_for(session).is_a?(Gateway)

      seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round
      BBS.log('door', 'crossed', door: @name.to_s, seconds: seconds, result: result)
    end

    def start(session, context)
      program = program_for(session)
      case program
      when FakeOS::Definition then FakeOS::Runner.new(session, program, context: context).run
      when Flow then run_flow(session, program, context)
      else program.call(session, context)
      end
    end

    def run_flow(session, flow, context)
      FlowRunner.new(session, context[:session_id], flow, context: context.dup).run
      session.write("#{Ansi::RESET}#{Ansi::CRLF}  #{Ansi::GREY}Press ENTER to return to the BBS...#{Ansi::RESET}")
      session.readline
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    end
  end
end
