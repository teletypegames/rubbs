# frozen_string_literal: true

module Rubbs
  module Common
    module AI
      # A counting semaphore: at most a given number of holders at once, the
      # others wait their turn for a while.
      class Semaphore
        # Creates a semaphore nobody holds.
        def initialize
          @mu    = Mutex.new
          @freed = ConditionVariable.new
          @held  = 0
        end

        # Runs the block once fewer than +limit+ hold the semaphore, waiting
        # up to +wait+ seconds for that. Returns the block's value; raises Busy
        # when the wait runs out.
        def hold(limit:, wait:)
          raise Busy, 'The model is busy, try again in a moment.' unless take(limit, wait)

          begin
            yield
          ensure
            give
          end
        end

        private

        def take(limit, wait)
          deadline = AI.monotonic + wait
          @mu.synchronize do
            while @held >= limit
              left = deadline - AI.monotonic
              return false unless left.positive?

              @freed.wait(@mu, left)
            end
            @held += 1
          end
        end

        def give
          @mu.synchronize do
            @held -= 1
            @freed.signal
          end
        end
      end

      # The one Semaphore of the process that every Client request holds.
      SLOTS = Semaphore.new
    end
  end
end
