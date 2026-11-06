# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # The supervisor's loop of a Rubbs::MultiRunner: once a second it takes
    # the ended boards' statuses and starts those due, and every few seconds
    # watches the deploy revision, probes and measures the boards, restarts
    # those that need it and writes the state (Status). SIGTERM or SIGINT ends
    # the loop and stops every board.
    module Supervision
      include Restarts

      # Seconds between two turns of the loop.
      TICK = 1
      # Seconds between two looks at <tt><root>/.revision</tt>.
      WATCH_EVERY = 5
      # Seconds between two health probes of every board.
      PROBE_EVERY = 30
      # Seconds between two memory checks of every board.
      MEASURE_EVERY = 30
      # Seconds between two writes of the state file.
      STATUS_EVERY = 10

      private

      def supervise
        @stop     = false
        @queue    = []
        @last     = Hash.new(-Float::INFINITY)
        @revision = read_revision
        %w[TERM INT].each { |sig| Signal.trap(sig) { @stop = true } }
        Rubbs.log('multi_runner', 'starting', boards: @children.map(&:name).join(','), revision: @revision, rubbs: Rubbs.version)
        until @stop
          tick(monotonic)
          sleep TICK
        end
        shutdown
      end

      def tick(now)
        reap(now)
        start_due(now) unless deploying?
        every(:watch, WATCH_EVERY, now) { watch_revision }
        every(:probe, PROBE_EVERY, now) { probe_all(now) }
        every(:measure, MEASURE_EVERY, now) { measure_all(now) }
        restart_next(now)
        @children.select { |child| child.overdue?(now) }.each(&:kill!)
        every(:status, STATUS_EVERY, now) { write_status }
      end

      def every(name, seconds, now)
        return if now - @last[name] < seconds

        @last[name] = now
        yield
      end

      def reap(now)
        loop do
          pid, status = Process.wait2(-1, Process::WNOHANG)
          break unless pid

          child = @children.find { |c| c.pid == pid } or next
          reason = child.ended(status, now)
          Rubbs.log(
            'multi_runner',
            "#{child.name} ended",
            level:      reason == :exit ? :warn : :info,
            bbs:        child.name,
            reason:     child.reason,
            restart_in: child.wait(now)
          )
        end
      rescue Errno::ECHILD
        nil
      end

      def start_due(now)
        @children.select { |child| child.due?(now) }.each do |child|
          pid = child.start(@revision, now)
          Rubbs.log('multi_runner', "#{child.name} started", bbs: child.name, pid: pid, port: child.port, revision: @revision)
        end
      end

      def write_status
        Status.write(@state, @children, revision: @revision, deploying: deploying?)
      rescue SystemCallError => e
        Rubbs.log('multi_runner', e, level: :warn)
      end

      def shutdown
        Rubbs.log('multi_runner', 'stopping', boards: @children.count(&:up?))
        @children.each { |child| child.stop(:shutdown, monotonic) }
        wait_for_children(monotonic + Rubbs.config.shutdown_seconds + 5)
        @children.select(&:up?).each(&:kill!)
        wait_for_children(monotonic + 1)
        write_status
        Rubbs.log('multi_runner', 'stopped')
      end

      def wait_for_children(deadline)
        until @children.none?(&:up?) || monotonic > deadline
          reap(monotonic)
          sleep 0.2
        end
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
