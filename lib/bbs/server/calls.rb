# frozen_string_literal: true

module BBS
  class Server
    # One call on a BBS::Server, from its session to its end: counted among
    # those on the line (BBS::Server::Stopping hangs up on them), its errors
    # logged, +on_session_end+ called and one log line of how it went.
    module Calls
      private

      def converse(client, address)
        session = Session.new(timed(client))
        started = monotonic
        ending  = :hung_up
        enlist(session)
        Log.with_session(session.session_id) { session.run }
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET, Errno::ETIMEDOUT
        ending = :dropped
      rescue StandardError => e
        ending = :error
        BBS.log('session', e, session: session&.session_id)
      ensure
        finish(client, address, session, ending, started)
      end

      # Counts the call of +session+ among those on the line.
      def enlist(session) = @mu.synchronize { @live[Thread.current] = session }

      # The end of a call: the line closed, the counts and +on_session_end+,
      # and one log line.
      def finish(client, address, session, ending, started)
        @mu.synchronize { @live.delete(Thread.current) }
        client.close rescue nil
        release(address)
        return unless session

        ending = :stopped if @stopping && ending != :error
        end_session(session)
        BBS.log('call', 'ended', session: session.session_id, seconds: (monotonic - started).round, end: ending)
      end

      def end_session(session)
        BBS.config.on_session_end&.call(session)
      rescue StandardError => e
        BBS.log('on_session_end', e, session: session.session_id)
      end
    end
  end
end
