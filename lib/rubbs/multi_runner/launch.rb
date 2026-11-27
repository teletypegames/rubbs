# frozen_string_literal: true

require 'fileutils'

module Rubbs
  class MultiRunner
    # What a Child's process does after the fork: its output into the pipe,
    # its folder, its environment, a fresh Rubbs.config, its +bbs.rb+, its
    # server. A Child includes it; it reads the Child's +ref+, +name+, +port+,
    # +max_sessions+ and settings.
    module Launch
      # The lock file, in a board's +data+ folder, of a board that does not drain.
      LOCK_FILE = '.rubbs-board.lock'

      private

      # Runs the board in this (forked) process. Never returns: exits 0 when
      # the server has stopped, 1 when the board failed to start or ended in
      # an error (written to the pipe first).
      def run_board(writer)
        into(writer)
        enter
        hold_lock unless drains?
        definition = ref.load_definition
        announce(definition)
        definition.run!
        exit!(0)
      rescue Exception => e # rubocop:disable Lint/RescueException
        warn("#{name}: #{e.class}: #{e.message}", *Array(e.backtrace).first(10).map { |frame| "  #{frame}" })
        exit!(1)
      end

      # Tells the supervisor the board's slug now, and that it listens once
      # its port is open.
      def announce(definition)
        $stderr.write("#{Output::NAME_LINE}#{definition.slug}\n")
        Rubbs.config.on_listen = ->(_server) { $stderr.write("#{Output::READY_LINE}\n") }
      end

      def into(writer)
        [$stdout, $stderr].each { |io| io.reopen(writer) && (io.sync = true) }
        writer.close
      end

      def enter
        %w[TERM INT].each { |sig| Signal.trap(sig, 'DEFAULT') }
        Process.setproctitle(name)
        Dir.chdir(ref.dir)
        environment.each { |key, value| ENV[key] = value }
        Rubbs.reset_config
      end

      def environment
        extra = @settings.fetch('env', {}).to_h { |key, value| [key.to_s, value.to_s] }
        own   = { 'BBS_PORT' => port.to_s, 'BBS_MAX_SESSIONS' => max_sessions.to_s }
        own['BBS_DRAIN_SECONDS'] = '0' unless drains?
        own.merge(extra)
      end

      # A board that does not drain holds <tt>data/.rubbs-board.lock</tt> in
      # its folder while it runs, so that its next process (of this
      # supervisor, or of the next image's beside it) starts only after this
      # one has ended. Says so (Output::WAITING_LINE) when it has to wait.
      def hold_lock
        FileUtils.mkdir_p('data')
        @lock = File.open(File.join('data', LOCK_FILE), File::RDWR | File::CREAT, 0o644)
        return if @lock.flock(File::LOCK_EX | File::LOCK_NB)

        $stderr.write("#{Output::WAITING_LINE}\n")
        @lock.flock(File::LOCK_EX)
      end
    end
  end
end
