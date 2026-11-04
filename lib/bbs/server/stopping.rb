# frozen_string_literal: true

module BBS
  class Server
    # How a BBS::Server stops (SIGTERM, Ctrl-C): in order, telling its
    # callers first.
    module Stopping
      # Seconds the callers still on after the shutdown wait get to end
      # their calls once they are hung up on.
      HANGUP_WAIT = 2
      # Seconds between two looks at the callers while the server waits for
      # them to leave.
      STOP_POLL = 0.2

      # Stops in order: closes the port (no new calls, and the health probe
      # fails), tells every caller BBS.config.shutdown_notice, waits up to
      # BBS.config.shutdown_seconds for them to leave and hangs up on the
      # rest (BBS::Hangup in their threads, so their transactions roll back
      # and +on_session_end+ runs). A second interrupt meanwhile stops at
      # once. Returns +nil+.
      def stop
        @stopping = true
        @listener&.close rescue nil
        sessions = live_sessions
        BBS.log('server', 'stopping', callers: sessions.size, wait: BBS.config.shutdown_seconds)
        unless sessions.empty?
          announce_stop(sessions)
          wait_for_callers
          hang_up_rest
        end
        BBS.log('server', 'stopped')
      rescue Interrupt
        BBS.log('server', 'stopped at once', level: :warn)
      end

      # Whether the server is stopping (#stop has begun).
      def stopping? = @stopping == true

      private

      # The sessions on the line now.
      def live_sessions = @mu.synchronize { @live.values }

      def announce_stop(sessions)
        notice = format(BBS.config.shutdown_notice, seconds: BBS.config.shutdown_seconds.ceil)
        sessions.each { |session| session.announce(notice) }
      end

      def wait_for_callers
        deadline = monotonic + BBS.config.shutdown_seconds
        sleep STOP_POLL while monotonic < deadline && !live_sessions.empty?
      end

      def hang_up_rest
        threads = @mu.synchronize { @live.keys }
        threads.each { |thread| thread.raise(Hangup.new('the board is stopping')) rescue ThreadError }
        deadline = monotonic + HANGUP_WAIT
        threads.each { |thread| thread.join([deadline - monotonic, 0].max) }
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
