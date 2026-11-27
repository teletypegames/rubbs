# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # How a Child makes way for its new code without dropping a call: the
    # new process starts beside the old one (both listen on the port,
    # Rubbs::Common::Line::Listener); once it says it listens (Output::READY_LINE)
    # the old one is drained (SIGUSR2, Rubbs::Common::Line::Server#drain): it takes
    # no more calls and ends when its last caller has left. A new process
    # that ends, or does not listen in READY_WAIT seconds, is given up, and
    # the old one goes on.
    #
    # A board with <tt>drain: false</tt> in the settings is never two at once:
    # it is stopped and started again (Child#stop), and its process holds a
    # lock (Launch) so that one of another supervisor waits for this one.
    module Handover
      # Seconds a new process has to listen before it is given up.
      READY_WAIT = 120
      # Old processes of a board draining at once at most: one more drains the oldest at once.
      MAX_DRAINING = 1
      # Seconds a draining process may outlive its drain before it is killed.
      DRAIN_SLACK = 30

      # The old process that waits for the new one to listen (a Hash: +pid+,
      # +revision+, +fingerprint+), or +nil+.
      attr_reader :previous

      # Whether the process has said it listens (Output::READY_LINE), and
      # whether it waits for the lock of an old one (Output::WAITING_LINE).
      attr_reader :ready, :waiting

      # Records that the process listens now. Returns +true+.
      def ready! = (@waiting = false) || (@ready = true)

      # Records that the process waits for the lock of an old one. Returns +true+.
      def waiting! = (@waiting = true)

      # The old processes that drain: Hashes of +pid+, +revision+, +since+
      # (a Time) and +deadline+ (monotonic seconds).
      def draining = @draining ||= []

      # Whether the board drains (the +drain+ setting, default +true+).
      def drains? = @settings.fetch('drain', true) != false

      # Whether a new process is starting beside an old one.
      def handing_over? = !@previous.nil?

      # Whether a process of the board runs: the current one, an old one
      # handing over or draining.
      def alive? = up? || handing_over? || draining.any?

      # Starts the process of +revision+ beside the running one, which goes
      # on until the new one listens (#settle). Returns the new pid.
      def hand_over(revision, now)
        @previous = { pid: @pid, revision: @revision, fingerprint: @fingerprint, started: @started, started_at: @started_at }
        @pid = nil
        @ready_by = now + READY_WAIT
        start(revision, now)
      end

      # Ends a hand-over that is due at +now+: the old process drains once
      # the new one listens; a new one that does not in time is stopped (and
      # the old one kept when it has ended). Returns +:handed+, +:given_up+
      # or +nil+.
      def settle(now)
        return unless handing_over? && up?
        return give_up(now) if !@ready && now > @ready_by
        return unless @ready

        drain_process(@previous, now)
        @previous = nil
        @restarts[:deploy] += 1
        :handed
      end

      # Drains every process of the board for good (the supervisor drains):
      # a board that drains gets SIGUSR2, one that does not is stopped.
      # Returns +nil+.
      def drain_all(now)
        return stop(:drain, now) unless drains?

        processes = [@previous, (current_process if up?)].compact

        processes.each { |process| drain_process(process, now, keep: true) }
        @pid = @previous = nil
      end

      # Whether +pid+ is a process of the board's.
      def owns?(pid) = [@pid, @previous&.[](:pid), *draining.map { |process| process[:pid] }].include?(pid)

      # Records that process +pid+ ended with +status+ at +now+: the current
      # one (#ended, or the old one back when a hand-over failed), the old
      # one of a hand-over, or a draining one. Returns the reason (a Symbol).
      def reaped(pid, status, now)
        return (handing_over? ? restore(status, now) : ended(status, now)) if pid == @pid
        return previous_ended if pid == @previous&.[](:pid)

        draining.reject! { |process| process[:pid] == pid }
        :drained
      end

      # Kills the draining processes past their deadline at +now+. Returns them.
      def kill_overdue_draining(now)
        draining.select { |process| now > process[:deadline] }.each { |process| process_signal('KILL', process[:pid]) }
      end

      # Signals the old processes of the board (handing over or draining),
      # not the current one (Child#stop, Child#kill!). Returns +nil+.
      def signal_others(name)
        [@previous&.[](:pid), *draining.map { |process| process[:pid] }].compact.each { |pid| process_signal(name, pid) }
        nil
      end

      # The hand-over facts of the board for the state file (Status).
      def handover_facts
        {
          drains:       drains?,
          ready:        ready,
          waiting:      waiting,
          handing_over: previous&.[](:pid),
          draining:     draining.map { |process| process.slice(:pid, :revision).merge(since: process[:since].utc.iso8601) }
        }
      end

      private

      def current_process = { pid: @pid, revision: @revision }

      def drain_process(process, now, keep: false)
        drain_oldest unless keep
        process_signal(Common::Line::Server::DRAIN_SIGNAL, process[:pid])
        draining << { pid: process[:pid], revision: process[:revision], since: Time.now, deadline: now + drain_limit }
      end

      def drain_oldest
        draining.first(draining.size - MAX_DRAINING + 1).each { |old| process_signal('TERM', old[:pid]) }
      end

      def drain_limit = Rubbs.config.drain_seconds + Rubbs.config.shutdown_seconds + DRAIN_SLACK

      def previous_ended
        @previous = nil
        :previous_ended
      end

      def give_up(now)
        @stopping = :handover
        @deadline = now + Rubbs.config.shutdown_seconds + 5
        process_signal('TERM', @pid)
        :given_up
      end

      def restore(status, now)
        @restarts[:handover] += 1
        @reason = "handover failed (#{status.exitstatus || status.termsig})"
        @pid, @revision, @fingerprint = @previous.values_at(:pid, :revision, :fingerprint)
        @started, @started_at = @previous.values_at(:started, :started_at)
        @previous = nil
        @stopping = nil
        @ready    = true
        @next     = now
        :handover
      end

      def process_signal(name, pid)
        Process.kill(name, pid) if pid
        nil
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
