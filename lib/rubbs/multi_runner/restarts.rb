# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # The restarts a Rubbs::MultiRunner asks for (Supervision runs them): the
    # boards a new deploy revision changed, one at a time; a board that fails
    # its health probes; a board over its memory. All in order
    # (Child#stop): the callers are told and get BBS_SHUTDOWN_SECONDS.
    module Restarts
      # The file whose change means a deploy brought new code.
      REVISION = '.revision'
      # The file that exists while a deploy copies the boards.
      DEPLOYING = '.deploying'
      # A <tt>.deploying</tt> older than this (seconds) is a deploy that died: it holds nothing back.
      DEPLOYING_STALE = 600

      private

      def watch_revision
        revision = read_revision
        return if revision == @revision || deploying?

        @revision = revision
        changed = @children.select { |child| child.ref.definition.nil? && Fingerprint.of(child.ref.dir) != child.fingerprint }
        (@children - changed).each { |child| child.revision = revision }
        @queue |= changed
        Rubbs.log('multi_runner', 'new revision', revision: revision, changed: changed.map(&:name).join(','))
      end

      def restart_next(now)
        if @current
          return if @current.stopping || !@current.up?

          @current = nil
        end
        @current = @queue.shift or return
        @current.up? ? @current.stop(:deploy, now) : (@current = nil)
      end

      def probe_all(now)
        @children.select(&:up?).map { |child| Thread.new { child.probe } }.each(&:join)
        @children.select { |child| child.unhealthy?(now) }.each do |child|
          Rubbs.log('multi_runner', "#{child.name} fails its health probe: restarting", level: :warn, bbs: child.name)
          child.stop(:health, now)
        end
      end

      def measure_all(now)
        @children.each(&:measure)
        @children.select(&:too_big?).each do |child|
          Rubbs.log(
            'multi_runner',
            "#{child.name} is over its memory: restarting",
            level:     :warn,
            bbs:       child.name,
            rss_bytes: child.rss_bytes
          )
          child.stop(:memory, now)
        end
      end

      def read_revision
        File.read(File.join(@root, REVISION)).strip
      rescue SystemCallError
        nil
      end

      def deploying?
        Time.now - File.mtime(File.join(@root, DEPLOYING)) < DEPLOYING_STALE
      rescue SystemCallError
        false
      end
    end
  end
end
