# frozen_string_literal: true

module BBS
  # At most +limit+ events per +per+ seconds for each key (a caller, an
  # address, a whole board), over a sliding window; thread-safe.
  #
  #   TIPS = BBS::RateLimit.new(limit: 3, per: 3600)
  #   if TIPS.allow?(BBS::RateLimit.caller_key(session)) then save(tip)
  #   else say("Again in #{TIPS.wait(key).ceil} seconds.")
  #   end
  #
  # Keys that have been quiet for +per+ seconds are forgotten.
  class RateLimit
    # Returns the key a caller's events are counted by: the IP address of a
    # caller on the internet (an IPv4-mapped one as IPv4), or
    # <tt>line:<session id></tt> for one behind a local proxy such as
    # bbs-web (BBS::Address.local?), whose address is the proxy's, and for a
    # line without an address.
    def self.caller_key(session)
      address = Address.parse(peer(session))
      address.nil? || Address.local?(address) ? "line:#{session.session_id}" : address.to_s
    end

    # Returns the IP address of +session+'s line as a String, or +nil+.
    def self.peer(session)
      session.line.remote_address.ip_address
    rescue StandardError
      nil
    end

    # Creates a limit of +limit+ events per +per+ seconds.
    def initialize(limit:, per:)
      @limit  = limit
      @per    = per
      @events = {}
      @pruned = monotonic
      @mu     = Mutex.new
    end

    # Returns whether +key+ may have one more event now, and counts it when
    # it may.
    def allow?(key)
      @mu.synchronize do
        events = recent(key)
        next false if events.size >= @limit

        events << monotonic
        true
      end
    end

    # Returns the seconds until +key+ may have an event, a Float; 0.0 when
    # it may now. Counts nothing.
    def wait(key)
      @mu.synchronize do
        events = recent(key)
        events.size < @limit ? 0.0 : [events.first + @per - monotonic, 0.0].max
      end
    end

    private

    # The times of +key+'s events in the window, oldest first.
    def recent(key)
      now = monotonic
      prune(now)
      events = (@events[key] ||= [])
      events.shift while events.any? && events.first <= now - @per
      events
    end

    def prune(now)
      return if now - @pruned < @per

      @events.delete_if { |_, events| events.empty? || events.last <= now - @per }
      @pruned = now
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
