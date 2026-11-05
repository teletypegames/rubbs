# frozen_string_literal: true

module Rubbs
  module Common
    module FakeOS
      # Entry point: plays the boot sequence then runs the shell until the user
      # quits or disconnects.
      class Runner
        # Creates a runner for +definition+ on +session+; +context+ is passed to
        # the Console.
        def initialize(session, definition, context: {})
          @session    = session
          @definition = definition
          @context    = context
        end

        # Runs a new Console. A dropped line ends it quietly.
        #
        # Returns +nil+ when the line dropped.
        def run
          Console.new(@session, @definition, @context).run
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          nil
        end
      end
    end
  end
end
