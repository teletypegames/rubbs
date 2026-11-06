# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # What a Child's process does after the fork: its output into the pipe,
    # its folder, its environment, a fresh Rubbs.config, its +bbs.rb+, its
    # server. A Child includes it; it reads the Child's +ref+, +name+, +port+,
    # +max_sessions+ and settings.
    module Launch
      private

      # Runs the board in this (forked) process. Never returns: exits 0 when
      # the server has stopped, 1 when the board failed to start or ended in
      # an error (written to the pipe first).
      def run_board(writer)
        into(writer)
        enter
        definition = ref.load_definition
        $stderr.write("#{Output::NAME_LINE}#{definition.slug}\n")
        definition.run!
        exit!(0)
      rescue Exception => e # rubocop:disable Lint/RescueException
        warn("#{name}: #{e.class}: #{e.message}", *Array(e.backtrace).first(10).map { |frame| "  #{frame}" })
        exit!(1)
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
        { 'BBS_PORT' => port.to_s, 'BBS_MAX_SESSIONS' => max_sessions.to_s }.merge(extra)
      end
    end
  end
end
