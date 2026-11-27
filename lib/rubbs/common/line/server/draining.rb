# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      class Server
        # How a Rubbs::Common::Line::Server makes way for the board's next
        # process (SIGUSR2, as a deploy sends once the next one listens on the
        # same port, see Listener): it takes no more calls, but the callers on
        # the line go on until they leave, for at most
        # Rubbs.config.drain_seconds; then it stops in order
        # (Rubbs::Common::Line::Server::Stopping#stop).
        module Draining
          # The signal that drains a server.
          DRAIN_SIGNAL = 'USR2'
          # Seconds between two looks at the callers while the server drains.
          DRAIN_POLL = 0.5

          # Raised in the server's thread by DRAIN_SIGNAL.
          class Drain < Exception; end # rubocop:disable Lint/InheritException

          # Drains: closes the port (the next process takes the new calls),
          # runs Rubbs.config.on_drain (the board ends its background work),
          # tells every caller Rubbs.config.drain_notice and waits until the
          # last has left or Rubbs.config.drain_seconds are over, then #stop.
          # With +drain_seconds+ 0 it stops at once. A SIGTERM meanwhile
          # stops at once too. Returns +nil+.
          def drain
            @draining = true
            @listener&.close rescue nil
            return stop unless Rubbs.config.drain_seconds.positive?

            sessions = live_sessions
            Rubbs.log('server', 'draining', callers: sessions.size, wait: Rubbs.config.drain_seconds)
            run_on_drain
            sessions.each { |session| session.announce(Rubbs.config.drain_notice) }
            wait_drained
            stop
          rescue Interrupt
            stop
          end

          # Whether the server is draining (#drain has begun).
          def draining? = @draining == true

          private

          def run_on_drain
            Rubbs.config.on_drain&.call
          rescue StandardError => e
            Rubbs.log('drain', e)
          end

          def wait_drained
            deadline = monotonic + Rubbs.config.drain_seconds
            sleep DRAIN_POLL while monotonic < deadline && !live_sessions.empty?
          end
        end
      end
    end
  end
end
