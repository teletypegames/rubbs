# frozen_string_literal: true

require_relative 'fake_os'

module BBS
  # A door: a program the caller steps into from the BBS, as in the doors of
  # the old boards. The BBS hands the telnet line over, the program talks to
  # the caller directly, and the line comes back when the program exits.
  #
  # The program is a BBS::FakeOS definition, a BBS::Flow, or anything that
  # responds to `call(session, context)`. A flow gets a copy of the caller's
  # context (so its `ask` steps cannot overwrite the BBS's own keys), and
  # since a flow ends without an exit command of its own, the door waits for
  # ENTER before handing the line back:
  #
  #   SERMO = BBS::Door.new(:sermo, Sermo::OS, label: '&SERMO')
  #   SERMO.run(session, ctx)
  #
  # Inside an Application, declare doors with the `door` DSL and let
  # `Builder#run` take the caller through them (see Application).
  class Door
    attr_reader :name, :label, :program

    def initialize(name, program, label: nil)
      raise ArgumentError, "Door #{name.inspect}: not a FakeOS definition or a callable" unless
        program.is_a?(FakeOS::Definition) || program.is_a?(Flow) || program.respond_to?(:call)

      @name    = name.to_sym
      @program = program
      @label   = label || name.to_s.upcase
    end

    # Hands the line to the program on a clean screen without mouse
    # reporting, and takes it back when the program returns.
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
