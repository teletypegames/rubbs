# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # The hand-overs and the drain of a Rubbs::MultiRunner's Supervision: a
    # board whose new code listens hands over (Handover); after SIGUSR2 every
    # board drains, and the supervisor only reaps until the last process has
    # ended (then Rubbs::MultiRunner#run! returns).
    module Draining
      private

      # The supervisor drains (SIGUSR2): every board once, then only reaps.
      def drain_tick(now)
        unless @drained_at
          @drained_at = now
          Rubbs.log('multi_runner', 'draining', boards: @children.count(&:alive?))
          @children.each { |child| child.drain_all(now) }
        end
        reap(now)
        kill_overdue(now)
        every(:status, Supervision::STATUS_EVERY, now) { write_status }
      end

      def kill_overdue(now)
        @children.select { |child| child.overdue?(now) }.each(&:kill!)
        @children.each { |child| child.kill_overdue_draining(now) }
      end

      def drained? = @drain && @drained_at && @children.none?(&:alive?)

      def finish_drain
        write_status
        Rubbs.log('multi_runner', 'drained')
      end

      def hand_over_due(now)
        @children.each do |child|
          case child.settle(now)
          when :handed then Rubbs.log('multi_runner', "#{child.name} handed over", bbs: child.name, pid: child.pid)
          when :given_up
            Rubbs.log('multi_runner', "#{child.name} did not listen: kept the old one", level: :warn, bbs: child.name)
          end
        end
      end

      def hand_over(child, now)
        pid = child.hand_over(@revision, now)
        Rubbs.log('multi_runner', "#{child.name} handing over", bbs: child.name, pid: pid, revision: @revision)
      end

      def log_old_ended(child, reason, pid) = Rubbs.log('multi_runner', "#{child.name} #{reason}", bbs: child.name, pid: pid)
    end
  end
end
