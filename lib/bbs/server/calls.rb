# frozen_string_literal: true

module BBS
  class Server
    # One call on a BBS::Server, from its session to its end: counted among
    # those on the line (BBS::Server::Stopping hangs up on them), its errors
    # logged, +on_session_end+ called and one log line of how it went
    # (#call_facts).
    module Calls
      private

      def converse(client, address)
        session = Session.new(timed(client))
        started = monotonic
        ending  = :hung_up
        enlist(session)
        Log.with_session(session.session_id, caller: session) { session.run }
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
        BBS.log('call', 'ended', **call_facts(session, started, ending))
      end

      # The facts of the +call ended+ line: the session, the caller's
      # address (+ip+), +seconds+, how it ended (+end+), where it came from
      # (+via+, BBS::Session#call_via), the +face+ (+modern+, +petscii+ or
      # +none+), the terminal's +cols+ and +rows+, whether it reported its
      # size (+naws+) and the signed-in caller's name (+user+, not for a
      # guest).
      def call_facts(session, started, ending)
        facts = {
          session: session.session_id,
          ip:      session.caller_ip,
          seconds: (monotonic - started).round,
          end:     ending,
          via:     session.call_via,
          face:    (session.face || :none).to_s,
          cols:    session.term_cols,
          rows:    session.term_rows,
          naws:    session.naws_reported?
        }
        user = session.caller_name
        user ? facts.merge(user: user) : facts
      end

      def end_session(session)
        BBS.config.on_session_end&.call(session)
      rescue StandardError => e
        BBS.log('on_session_end', e, session: session.session_id)
      end
    end
  end
end
