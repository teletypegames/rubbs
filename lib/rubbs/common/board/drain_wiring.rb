# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      # How a Rubbs::Common::Board::BoardDefinition ends: it drains
      # (Rubbs::Common::Line::Server#drain: the board's next process takes the new calls
      # while the callers on this one go on: its #on_drain blocks, the
      # Central's HTTP, the domain object's background work), and it stops
      # after the server (#stop).
      module DrainWiring
        # A block run once with the domain object when the server drains,
        # before the domain's own +drain+: an HTTP API beside the telnet port
        # shut, say, so that the next process answers it.
        #
        #   on_drain { api.stop }
        def on_drain(&block) = drain_hooks << block

        # Makes way for the board's next process: the #on_drain blocks, the
        # Central's HTTP shut (Rubbs::Common::Central::Server#drain), the domain
        # object's +drain+ (Rubbs::Common::Board::Domain#drain).
        # <tt>Rubbs.config.on_drain</tt> calls it. An error is logged, not
        # raised. Returns +nil+.
        def drain!
          drain_hooks.each { |hook| hook.call(@board) }
          Rubbs.config.central&.server&.drain
          @board.drain if @board.respond_to?(:drain)
          nil
        rescue StandardError => e
          Rubbs.log('drain', e)
        end

        # Ends the board after the server: the #on_stop blocks, then the domain
        # object's +stop+ (Rubbs::Common::Board::Domain#stop). An error is logged, not raised.
        # Returns +nil+.
        def stop
          @on_stop.each { |hook| hook.call(@board) }
          Rubbs.config.central&.server&.stop
          @board.stop if @board.respond_to?(:stop)
          nil
        rescue StandardError => e
          Rubbs.log('stop', e)
        end

        private

        def drain_hooks = @drain_hooks ||= []

        def configure_drain = (Rubbs.config.on_drain = -> { drain! })
      end
    end
  end
end
