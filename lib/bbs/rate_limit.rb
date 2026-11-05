# frozen_string_literal: true

require 'monitor'

module BBS
  # At most +limit+ events per +per+ seconds for each key (a caller, an
  # address, a whole board), over a sliding window; thread-safe.
  #
  #   TIPS = BBS::RateLimit.new(limit: 3, per: 3600)
  #   if TIPS.allow?(BBS::RateLimit.caller_key(session)) then save(tip)
  #   else say("Again in #{TIPS.wait(key).ceil} seconds.")
  #   end
  #
  # Several limits at once (a caller's and the whole board's) are checked
  # with ::allow_all?, which counts the event in every limit or in none.
  # #room? and #record check and count apart, for an event counted only
  # when it went wrong (a failed login):
  #
  #   return locked_out unless LOGINS.room?(key)
  #   LOGINS.record(key) unless password_ok?
  #
  # By default the events live in memory and a restart forgets them; with
  # a +store+ (the board's Sequel::Database) they are kept in its +rate_limit_events+ table
  # under the limit's +name+, so a lockout outlasts a restart. Keys that
  # have been quiet for +per+ seconds are forgotten either way.
  class RateLimit
    # The one lock of every limit, so ::allow_all? can check several at
    # once; reentrant.
    LOCK = Monitor.new

    # Returns the key a caller's events are counted by: the IP address of a
    # caller on the internet (an IPv4-mapped one as IPv4), the forwarded one
    # for a call through another board's gateway (Telnet::Forwarded#caller_ip),
    # or <tt>line:<session id></tt> for one behind a local proxy that does
    # not forward it, such as bbs-web (BBS::Address.local?), and for a line
    # without an address.
    def self.caller_key(session)
      address = Address.parse(peer(session))
      address.nil? || Address.local?(address) ? "line:#{session.session_id}" : address.to_s
    end

    # Returns the caller's IP address of +session+ as a String (the
    # forwarded one when believed, see Telnet::Forwarded#caller_ip), or
    # +nil+.
    def self.peer(session)
      session.respond_to?(:caller_ip) ? session.caller_ip : session.line.remote_address.ip_address
    rescue StandardError
      nil
    end

    # Returns whether every limit has room for its key, and then counts the
    # event in each; when one has no room, nothing is counted. +checks+ is
    # an Array of <tt>[limit, key]</tt> pairs.
    #
    #   BBS::RateLimit.allow_all?([[PER_CALLER, key], [PER_BOARD, :all]])
    #
    # A refusal writes a +rate limit refused+ line (level +info+) with the
    # +limit+: the #name of each full limit (+unnamed+ for one without),
    # joined by commas.
    def self.allow_all?(checks)
      full = LOCK.synchronize do
        full = checks.reject { |limit, key| limit.room?(key) }
        checks.each { |limit, key| limit.record(key) } if full.empty?
        full
      end
      return true if full.empty?

      BBS.log('rate limit', 'refused', limit: full.map { |limit, _| limit.name || 'unnamed' }.uniq.join(','))
      false
    end

    # Creates a limit of +limit+ events per +per+ seconds. With a +store+
    # (a Sequel::Database) the events are kept there under +name+ (a String,
    # required then); without one, in memory. The +name+ also tells the
    # limit in the log line of a refusal.
    def initialize(limit:, per:, store: nil, name: nil)
      raise ArgumentError, 'a stored RateLimit needs a name' if store && name.to_s.empty?

      @limit  = limit
      @per    = per
      @name   = name&.to_s
      @events = store ? Table.new(store, name.to_s) : Memory.new
    end

    # The limit's name (a String, the +limit+ of its log lines), or +nil+.
    attr_reader :name

    # Returns whether +key+ may have one more event now, and counts it when
    # it may.
    def allow?(key) = RateLimit.allow_all?([[self, key]])

    # Returns whether +key+ may have one more event now. Counts nothing.
    def room?(key) = LOCK.synchronize { recent(key).size < @limit }

    # Counts one event of +key+ now, room or not. Returns +nil+.
    def record(key)
      LOCK.synchronize { @events.add(key, @events.now) }
      nil
    end

    # Returns the seconds until +key+ may have an event, a Float; 0.0 when
    # it may now. Counts nothing.
    def wait(key)
      LOCK.synchronize do
        times = recent(key)
        times.size < @limit ? 0.0 : [times[-@limit] + @per - @events.now, 0.0].max
      end
    end

    private

    # The times of +key+'s events in the window, oldest first.
    def recent(key) = @events.since(key, @events.now - @per)

    # The events of a limit in memory, by monotonic time.
    class Memory
      # Creates an empty store.
      def initialize
        @times  = {}
        @pruned = now
      end

      # The current time of this store: monotonic seconds.
      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # The times of +key+'s events after +start+, oldest first; older ones
      # are dropped.
      def since(key, start)
        prune(start)
        times = @times[key] or return []
        times.shift while times.any? && times.first <= start
        times
      end

      # Keeps an event of +key+ at +time+.
      def add(key, time) = (@times[key] ||= []) << time

      private

      # Forgets the keys whose last event is before +start+, once a window.
      def prune(start)
        return if start < @pruned

        @times.delete_if { |_, times| times.empty? || times.last <= start }
        @pruned = now
      end
    end

    # The events of a limit in a table of the board's database (a
    # Sequel::Database), by wall-clock time, so they outlast a restart.
    class Table
      # The table every stored limit keeps its events in.
      NAME = :rate_limit_events

      # Uses (and creates) the table in +db+ for the limit called +name+.
      def initialize(db, name)
        db.create_table?(NAME) do
          String :name, null: false
          String :key, null: false
          Float :at, null: false
          index %i[name key at]
        end
        @events = db[NAME]
        @name   = name
      end

      # The current time of this store: Unix seconds.
      def now = Time.now.to_f

      # The times of +key+'s events after +start+, oldest first; the older
      # events of the limit are deleted.
      def since(key, start)
        @events.where(name: @name).where { at <= start }.delete
        @events.where(name: @name, key: key.to_s).order(:at).select_map(:at)
      end

      # Keeps an event of +key+ at +time+.
      def add(key, time) = @events.insert(name: @name, key: key.to_s, at: time)
    end
  end
end
