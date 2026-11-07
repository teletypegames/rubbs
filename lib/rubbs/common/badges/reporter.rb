# frozen_string_literal: true

module Rubbs
  module Common
    module Badges
      # A board's half of the badges: it sends the events of its signed-in
      # callers to the Central's Service in a thread of its own (a caller
      # never waits for it) and tells the caller what they earned
      # (Rubbs::Common::Line::Session#announce, Badges.announcement). Only
      # the events some badge of the catalog counts go out
      # (Catalog#counts?); a guest's go nowhere, but the first one a badge
      # would count tells the guest, once a call, Badges.guest_hint (when the
      # network set one). Rubbs.board's +badges+
      # makes one; Rubbs::Common::Line::Session#achieve and the events of
      # Catalog::BUILT_IN come here.
      class Reporter
        # The events waiting to go, at most; more are dropped.
        QUEUE = 500

        # The board's name in the badges (Badge#board).
        attr_reader :board

        # A reporter for +board+ that sends through +proxy+ (a
        # Rubbs::Common::Central::Proxy of Service), counting by +catalog+.
        def initialize(proxy, board:, catalog: Badges.catalog)
          @proxy   = proxy
          @board   = board.to_s
          @catalog = catalog
          @queue   = Thread::Queue.new
          @called  = ObjectSpace::WeakMap.new
          @hinted  = ObjectSpace::WeakMap.new
          @mutex   = Mutex.new
        end

        # Sends the event +name+ with +fields+ of the caller on +session+,
        # when they are signed in and a badge counts it. Returns the queued
        # entry, +nil+ when nothing went.
        def report(session, name, fields = {})
          identity = session.respond_to?(:identity) ? session.identity : nil
          return nil unless @catalog.counts?(name, @board, fields)
          return hint(session) unless identity&.signed_in?
          return nil if @queue.size >= QUEUE

          start
          entry = [session, Central::Actor.of(session), name.to_s, fields.to_h, session_id(session), via(session)]
          @queue << entry
          entry
        end

        # The +call+ event, once a call for each account signed in on it.
        # Returns the queued entry (#report), or +nil+.
        def called(session)
          id = session.respond_to?(:identity) && session.identity.signed_in? ? session.identity.id : nil
          return nil if id.nil? || @called[session] == id

          @called[session] = id
          report(session, :call)
        end

        # The +hangup+ event of a call that had a +call+: its +minutes+.
        # Returns the queued entry (#report), or +nil+.
        def hung_up(session)
          return nil unless @called[session] && session.respond_to?(:started_at)

          report(session, :hangup, minutes: ((Time.now - session.started_at) / 60).floor)
        end

        # Sends what is queued now, in this thread (for a test or a stop).
        def flush
          send_one(@queue.pop) until @queue.empty?
        end

        private

        # Tells a guest once a call what an account would have collected.
        def hint(session)
          text = Badges.guest_hint
          return nil if text.nil? || @hinted[session]

          @hinted[session] = true
          session.announce(text) if session.respond_to?(:announce)
          nil
        end

        def start
          @mutex.synchronize do
            @thread = nil unless @thread&.alive?
            @thread ||= Thread.new { loop { send_one(@queue.pop) } }
          end
        end

        def send_one((session, actor, name, fields, call, via))
          answer = @proxy.call(:record, actor, event: name, fields: fields, call: call, via: via, board: @board)
          Array(answer['earned']).each { |badge| session.announce(Badges.announcement(badge)) }
          Array(answer['notices']).each { |text| session.announce(text) }
        rescue StandardError => e
          Rubbs.log('badges', e, level: :warn)
        end

        def session_id(session) = session.respond_to?(:session_id) ? session.session_id : nil

        def via(session) = session.respond_to?(:call_via) ? session.call_via : nil
      end
    end
  end
end
