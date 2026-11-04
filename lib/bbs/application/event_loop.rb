# frozen_string_literal: true

module BBS
  class Application
    # The event loop of an Application: read a key, make it a BBS::Event,
    # hand it down the chain of receivers, tick while the caller is quiet,
    # and end at the idle limit.
    module EventLoop
      # The receivers an event goes to after the window switching keys, in
      # order; the first that takes it ends the chain.
      RECEIVERS = %i[window_event menubar_event statusbar_event root_event].freeze

      # Main event loop. Uses a short read timeout to fire periodic ticks for
      # UI polling (chat, clock) while still detecting hard idle disconnects.
      #
      # Draws the screen, reads a key with a one-second timeout and dispatches
      # it as a BBS::Event: an open menubar first, then window switching keys,
      # the top window, the menubar, the statusbar and the root container's
      # focused widget. A second without input calls #tick!. After the idle
      # limit without input (the session's +idle_seconds+, set from
      # BBS.config.idle_seconds) the +on_idle+ callable runs; unless it
      # calls Application#keep_on, the loop shows a message and ends.
      # A handler's StandardError is logged and the loop goes on. Ends when a
      # handler returns :halt, #stop! is called or the line drops (see
      # #line_lost?), then shows the cursor and clears the screen.
      def run
        @running = true
        start_idle
        listen_announcements
        event_turn while @running
      rescue *LINE_DROPPED
        @line_lost = true
        nil
      ensure
        @session.on_announce(nil) if @session.respond_to?(:on_announce)
        @session.write("#{Ansi::SHOW_CURSOR}#{Ansi::CLEAR}")
        @running = false
      end

      # The idle limit in seconds for this run: the session's +idle_seconds+
      # when it has one, else BBS.config.idle_seconds; +nil+ means no limit.
      def idle_limit
        @session.respond_to?(:idle_seconds) ? @session.idle_seconds : BBS.config.idle_seconds
      end

      # Periodic tick: notify on_tick callback and let each open window pull
      # any asynchronous updates by overriding BBS::Window#tick.
      def tick!
        refresh_status
        @desktop&.tick
        @on_tick&.call(self)
        @windows.each { |w| w.tick(self) }
      end

      # Makes the event loop end after the current event.
      def stop! = (@running = false)

      # True when the run ended because the line did (a hang-up, the idle
      # limit): no door is opened after it.
      def line_lost? = @line_lost == true

      private

      # One turn of the loop: draw, read a key, act on it.
      def event_turn
        show_announcements
        render_screen
        key = @session.readkey(timeout: TICK_SECONDS)
        return lose_line if key.nil?
        return idle_tick if key == :idle

        @idle_elapsed = 0.0
        stop! if handle_safely(event_of(key)) == :halt
      end

      def lose_line
        @line_lost = true
        stop!
      end

      def start_idle
        @idle_elapsed = 0.0
        @idle_max     = idle_limit
      end

      # A second without a key: a tick, and the idle limit when it is reached.
      def idle_tick
        @idle_elapsed += TICK_SECONDS
        tick!
        return unless @idle_max && @idle_elapsed >= @idle_max

        @kept_on = false
        @on_idle&.call(self)
        return start_idle if @kept_on

        Dialogs.message(self, "Disconnected after #{@idle_max.to_i}s idle.", title: 'Idle')
        render_screen
        sleep IDLE_MESSAGE_WAIT
        lose_line
      end

      def event_of(key)
        case key
        when Telnet::MouseEvent then Event.mouse(key)
        when :idle              then Event.idle
        else Event.key(key)
        end
      end

      # Dispatches +event+; one handler's fault must not end the caller's
      # whole session, so its error is logged and the loop goes on.
      def handle_safely(event)
        dispatch(event)
      rescue IOError, SystemCallError
        raise
      rescue Abort
        nil
      rescue StandardError => e
        BBS.log('event', e)
        nil
      end

      # An open menubar takes every event (its keys must beat any modal
      # window's focused widget); otherwise the switching keys, then the
      # RECEIVERS. Returns +:halt+ to end the run.
      def dispatch(event)
        return (@menubar.handle_event(event) == :halt ? :halt : nil) if @menubar&.open?
        return nil if switch_window(event)

        RECEIVERS.each do |receiver|
          result = send(receiver, event)
          return result if result
        end
        nil
      end

      # The top window; +:close_window+ closes it.
      def window_event(event)
        window = top_window
        result = window&.handle_event(event)
        return result unless result == :close_window

        close_window(window)
        :handled
      end

      # The menubar handles Alt-letter, F10 and its own keys when closed.
      def menubar_event(event) = @menubar&.handle_event(event)

      def statusbar_event(event) = @statusbar&.handle_event(event)

      # The focused widget of the root panel, the background UI.
      def root_event(event)
        @root_focus ||= FocusManager.new(@root)
        @root_focus.handle_focus_key(event) || @root_focus.dispatch(event)
      end
    end
  end
end
