# frozen_string_literal: true

module Rubbs
  module Test
    # A Session whose keys come from a test while the call runs in another
    # thread (Rubbs::Test::Case#call): #press hands a key over and returns
    # once the board has taken it and waits for the next one, so what the
    # board drew in between can be looked at.
    #
    #   line = Rubbs::Test::ScriptedLine.new(petscii: true)
    #   Thread.new { UI::Petscii.new(line, {}, board).run }
    #   line.press('r')
    #   Rubbs::Test.screen_text(line)
    class ScriptedLine < Session
      # Seconds #press waits for the board to take a key and ask for the next.
      WAIT = 5

      # Raised by #press when the board does not ask for the next key in
      # time (it hangs, or reads in a way the line does not see).
      class Stuck < StandardError; end

      # A line as Session.new makes one, its keys handed over by #press.
      def initialize(**)
        super
        @queue = Thread::Queue.new
        @mutex = Mutex.new
        @asked = ConditionVariable.new
        @taken = 0
        @waiting = false
      end

      # The next key the test pressed; waits for one. With a +timeout+ (a
      # board's tick) +:idle+ when none came in that many seconds. +nil+
      # after #hang_up.
      def readkey(timeout: nil, **)
        @mutex.synchronize do
          @waiting = true
          @asked.broadcast
        end
        key = next_key(timeout)
        @mutex.synchronize do
          @waiting = false
          @taken += 1 unless key == :idle
        end
        key
      end

      # The next line typed: the keys up to an +:enter+ joined, or +nil+ when
      # the line drops first.
      def readline(**)
        typed = +''
        while (key = readkey)
          return typed if key == :enter

          typed << key if key.is_a?(String)
        end
        nil
      end

      # Hands +key+ to the board and waits until it has taken it and asks
      # for the next, or the call (+runner+, its Thread) has ended. Raises
      # Stuck after WAIT seconds.
      def press(key, runner: nil)
        before = @mutex.synchronize { @taken }
        @queue << key
        until_asked(before, runner)
      end

      # Waits until the board waits for a key (or +runner+ has ended).
      # Raises Stuck after WAIT seconds.
      def until_asked(before = -1, runner = nil)
        deadline = monotonic + WAIT
        @mutex.synchronize do
          until (@waiting && @taken > before) || (runner && !runner.alive?)
            left = deadline - monotonic
            raise Stuck, stuck_words(runner) if left <= 0

            @asked.wait(@mutex, [left, 0.05].min)
          end
        end
      end

      # Drops the line: the board's next read answers +nil+.
      def hang_up = @queue.close

      private

      def stuck_words(runner)
        where = Array(runner&.backtrace).first(3).join(' < ')
        "the board did not ask for a key within #{WAIT}s#{" (at #{where})" unless where.empty?}"
      end

      def next_key(timeout)
        return @queue.pop unless timeout

        key = @queue.pop(timeout: timeout)
        key.nil? && !@queue.closed? ? :idle : key
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
