# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # One board of a Rubbs::MultiRunner and its process: started (forked),
    # probed, measured, stopped, and started again after it ended.
    class Child
      include Launch

      # Seconds after a start before failed health probes count.
      START_GRACE = 120
      # Failed probes in a row that restart a board.
      HEALTH_FAILURES = 3
      # Checks in a row over the +memory+ limit that restart a board.
      MEMORY_STRIKES = 2
      # The longest wait before a board that keeps ending is started again.
      MAX_BACKOFF = 60
      # Seconds a board must have run for its next end to be waited out from 1 second again.
      STEADY = 60
      # The units of a +memory+ setting (<tt>160m</tt>).
      UNITS = { '' => 1, 'k' => 1024, 'm' => 1024**2, 'g' => 1024**3 }.freeze

      # The board (a BoardRef).
      attr_reader :ref

      # The process id (+nil+ when the board is not running), when it was
      # started (a Time), the Fingerprint of its code then, the last health
      # probe's verdict (+nil+ before the first) and callers, its resident
      # memory in bytes, its restarts by reason (a Hash) and the last reason.
      attr_reader :pid, :started_at, :fingerprint, :healthy, :callers, :rss_bytes, :restarts, :reason

      # The board's technical name (from its first JSON log line), and the
      # deploy revision its code is of.
      attr_accessor :slug, :revision

      # [ref]      the BoardRef
      # [settings] the board's settings (Rubbs::MultiRunner.new)
      # [output]   the Output its lines go to
      def initialize(ref, settings, output:)
        @ref      = ref
        @settings = settings
        @output   = output
        @backoff  = 0
        @next     = 0
        @failures = 0
        @strikes  = 0
        @restarts = Hash.new(0)
      end

      # The board's name (its folder's).
      def name = ref.name

      # The board's telnet port: +port+ of the settings, else BBS_PORT, else 2323.
      def port = Integer(@settings['port'] || ENV['BBS_PORT'] || 2323)

      # Callers at once: +max_sessions+ of the settings, else BBS_MAX_SESSIONS, else 100.
      def max_sessions = Integer(@settings['max_sessions'] || ENV['BBS_MAX_SESSIONS'] || 100)

      # The +memory+ setting in bytes, or +nil+ without one.
      def memory_limit
        value = @settings['memory'] or return nil
        number, unit = value.to_s.downcase.match(/\A(\d+)\s*([kmg]?)b?\z/)&.captures
        raise ArgumentError, "#{name}: memory #{value.inspect} is not like 160m" unless number

        Integer(number) * UNITS.fetch(unit)
      end

      # Whether the board's process runs.
      def up? = !@pid.nil?

      # Whether the board is being stopped (and why: a Symbol), or +nil+.
      attr_reader :stopping

      # Whether the board is down and its wait is over at +now+ (monotonic seconds).
      def due?(now) = !up? && now >= @next

      # Starts the board's process, its code of +revision+. Returns the pid.
      def start(revision, now)
        @fingerprint = ref.definition ? nil : Fingerprint.of(ref.dir)
        reader, writer = IO.pipe
        @pid = fork do
          reader.close
          run_board(writer)
        end
        writer.close
        @output.pump(reader, self)
        started(revision, now)
        @pid
      end

      # Asks the board to stop (SIGTERM: it tells its callers and waits
      # BBS_SHUTDOWN_SECONDS for them) for +reason+ (+:deploy+, +:health+,
      # +:memory+, +:shutdown+). Returns +nil+.
      def stop(reason, now)
        return unless up? && !@stopping

        @stopping = reason
        @deadline = now + Rubbs.config.shutdown_seconds + 5
        signal('TERM')
      end

      # Whether a board asked to stop is still up past its time at +now+.
      def overdue?(now) = up? && !@stopping.nil? && now > @deadline

      # Kills the board's process (SIGKILL). Returns +nil+.
      def kill! = signal('KILL')

      # Records that the process ended with +status+ (a Process::Status) at
      # +now+, and when it may start again: at once after a stop asked for,
      # else after a wait that doubles while it keeps ending soon. Returns the
      # reason (a Symbol: the stop's, or +:exit+).
      def ended(status, now)
        reason = @stopping || :exit
        @restarts[reason] += 1 unless reason == :shutdown
        @reason   = reason == :exit ? "exit #{status.exitstatus || status.termsig}" : reason.to_s
        @pid      = nil
        @stopping = nil
        @healthy  = nil
        @next     = now + (reason == :exit ? backoff(now) : 0)
        reason
      end

      # Seconds until the board is started again (0 when it is due).
      def wait(now) = [@next - now, 0].max.round

      # Probes the board's health (Rubbs::Common::Line::Health.ask) and keeps
      # the verdict and the callers. Returns the verdict.
      def probe
        ok, line = Common::Line::Health.ask(port: port, timeout: 5)
        @callers  = line[%r{\AOK (\d+)/}, 1]&.to_i if ok
        @failures = ok ? 0 : @failures + 1
        @healthy  = ok
      end

      # Whether the board has failed HEALTH_FAILURES probes in a row after
      # its START_GRACE, at +now+.
      def unhealthy?(now) = up? && @stopping.nil? && now - @started > START_GRACE && @failures >= HEALTH_FAILURES

      # Reads the board's resident memory (Linux, <tt>/proc</tt>) and counts
      # the checks over its limit. Returns the bytes, or +nil+.
      def measure
        @rss_bytes = up? ? self.class.rss(@pid) : nil
        limit      = memory_limit
        @strikes   = limit && @rss_bytes && @rss_bytes > limit ? @strikes + 1 : 0
        @rss_bytes
      end

      # Whether the board has been over its memory limit MEMORY_STRIKES checks in a row.
      def too_big? = up? && @stopping.nil? && @strikes >= MEMORY_STRIKES

      # The resident memory of process +pid+ in bytes, or +nil+ off Linux.
      def self.rss(pid)
        kilobytes = File.read("/proc/#{pid}/status")[/^VmRSS:\s+(\d+) kB/, 1]
        kilobytes && (Integer(kilobytes) * 1024)
      rescue SystemCallError
        nil
      end

      # The board's state for the state file (Status).
      def to_h
        {
          name:               name,
          slug:               slug || name,
          pid:                pid,
          up:                 up?,
          healthy:            healthy,
          callers:            callers,
          max_sessions:       max_sessions,
          port:               port,
          started_at:         started_at&.utc&.iso8601,
          rss_bytes:          rss_bytes,
          memory_limit_bytes: memory_limit,
          revision:           revision,
          restarts:           restarts.transform_keys(&:to_s),
          last_reason:        reason
        }
      end

      private

      def started(revision, now)
        @revision   = revision
        @started    = now
        @started_at = Time.now
        @failures   = 0
        @strikes    = 0
      end

      def backoff(now)
        @backoff = now - @started > STEADY ? 1 : (@backoff * 2).clamp(1, MAX_BACKOFF)
      end

      def signal(name)
        Process.kill(name, @pid) if @pid
        nil
      rescue Errno::ESRCH
        nil
      end
    end
  end
end
