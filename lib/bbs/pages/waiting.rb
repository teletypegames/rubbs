# frozen_string_literal: true

module BBS
  class Pages
    # How a BBS::Pages runner waits for the caller: a key with the timers
    # of #every running, a page shown until an answer, a line of text, and
    # the line handed over to someone else.
    module Waiting
      # The next key of the caller (see BBS::Telnet#readkey), the timers of
      # #every run while waiting: each wait of the shortest timer's seconds
      # without a key counts that long for every timer. #quit when the caller
      # is silent past the session's idle time while a timer polls. Raises
      # BBS::Hangup when the caller hangs up.
      def wait_key
        idle = 0.0
        loop do
          step = poll
          key = @session.readkey(timeout: step)
          raise Hangup if key.nil?
          return key unless key == :idle

          idle += step.to_f
          idle_out(idle)
          fire_timers(step.to_f)
        end
      end

      # Shows +page+ over the one on top until an answer: each key goes to
      # the block, and the first value it returns that is not +nil+
      # (+false+ counts) is the answer; without a block the first key is.
      # Then +page+ goes and the screen is repainted. The page's own keys
      # are not run. Returns the answer.
      #
      #   yes = show(Question.new('Dial anyway?')) { |k| { 'y' => true, 'n' => false }[k.to_s.downcase] }
      def show(page)
        answer = over(page) do
          redraw
          loop do
            key = wait_key
            value = block_given? ? yield(key) : key
            break value unless value.nil?
          end
        end
        redraw
        answer
      end

      # Reads a line of text (a BBS::Pages::Line, kept in #line while it is
      # read so the screen can draw it), repainting after each key. Returns
      # the text on RETURN, +nil+ when given up.
      #
      # [label] the words before the line
      # [text]  the text to start from
      # [max]   the most characters, +nil+ for no limit
      # [hint]  a line of help
      def read_line(label = nil, text: '', max: nil, hint: nil)
        @line = Line.new(label: label, hint: hint, text: text, max: max)
        redraw
        loop do
          case @line.key(wait_key)
          when :done then return @line.text
          when :cancel then return nil
          end
          redraw
        end
      ensure
        @line = nil
      end

      # Gives the screen and the keys to the block: a gateway to another
      # board, a banner played as it came. Before it the screen is cleared
      # (MODERN_CLEAR, or the C64's character set and CLR); after it a modern
      # terminal gets MODERN_RESTORE (mouse reporting off, the cursor shown)
      # and the next repaint is the whole screen. No repaint happens inside
      # it, not even by a timer. Returns the block's value.
      #
      #   hand_over { BBS::Gateway.new(host: 'bbs.example.org', port: 23).call(session) }
      def hand_over
        @handed = true
        clear_for_hand_over
        value = yield
        @session.write(MODERN_RESTORE) unless petscii?
        value
      ensure
        @handed = false
        @shown  = nil
        @cursor_shown = true
      end

      private

      # Runs the block with +page+ on top, then takes it off however the
      # block ends.
      def over(page)
        page.pages = self
        @stack.push(page)
        yield
      ensure
        @stack.pop if @stack.last.equal?(page)
      end

      def timers = self.class.timers.map { |t| [self, t] } + (page ? page.class.timers.map { |t| [page, t] } : [])

      # Seconds to wait for a key before the timers are looked at; +nil+
      # (wait for ever) without one.
      def poll = timers.map { |_, t| t.seconds }.min

      def fire_timers(step)
        timers.each do |owner, timer|
          id = [owner.object_id, timer.object_id]
          @fired[id] = @fired.fetch(id, 0.0) + step
          next if @fired[id] < timer.seconds - 0.001

          @fired[id] = 0.0
          owner.instance_exec(&timer.action)
        end
      end

      def idle_out(idle)
        limit = @session.respond_to?(:idle_seconds) ? @session.idle_seconds : nil
        quit if limit && idle >= limit
      end
    end

    include Waiting
  end
end
