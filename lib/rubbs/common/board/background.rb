# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      # Work a board does in a thread of its own, out of the callers' way: an
      # index loaded at boot, a catalog refreshed every hour. An error is
      # logged (Rubbs.log) and the work tried again after a pause that doubles
      # up to +max_retry+ seconds, so a service that is down for an hour costs
      # a few log lines, not a crashed board or a busy loop. Start one with
      # Rubbs.background:
      #
      #   Rubbs.background('index') { wiki.load_index }                 # once, until it succeeds
      #   Rubbs.background('catalog refresh', every: 3600) { library.refresh }
      class Background
        # Seconds before the first retry, by default.
        RETRY_AFTER = 5
        # The longest pause between retries, by default, in seconds.
        MAX_RETRY = 300

        # Prepares the work; see Rubbs.background for the arguments.
        def initialize(name, every: nil, retry_after: RETRY_AFTER, max_retry: MAX_RETRY, &work)
          @name        = name
          @every       = every
          @retry_after = retry_after
          @max_retry   = max_retry
          @work        = work
        end

        # Starts the work in a new Thread named after it and returns the
        # Thread.
        def start
          Thread.new { run }.tap do |thread|
            thread.name = "bbs: #{@name}"
            thread.report_on_exception = false
          end
        end

        # Runs the work in the calling thread: once until it succeeds, or
        # forever every +every+ seconds. Returns when a single run succeeded.
        def run
          delay = @retry_after
          loop do
            @work.call
            return unless @every

            delay = @retry_after
            sleep @every
          rescue StandardError => e
            delay = failed(e, delay)
          end
        end

        private

        # Logs +error+, waits +delay+ seconds and returns the next delay.
        def failed(error, delay)
          Rubbs.log(@name, error, level: :warn, retry_in: delay)
          sleep delay
          [delay * 2, @max_retry].min
        end
      end
    end
  end
end
