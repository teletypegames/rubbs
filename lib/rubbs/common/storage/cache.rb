# frozen_string_literal: true

module Rubbs
  module Common
    module Storage
      # A thread-safe in-memory cache of computed values, for the answers of a
      # slow service: each value lives +ttl+ seconds, the least recently used
      # go first when the cache is full, and one computation runs per key at a
      # time.
      #
      #   ARTICLES = Rubbs::Common::Storage::Cache.new(ttl: 600, max_entries: 500, max_bytes: 8 * 1024 * 1024)
      #   ARTICLES.fetch([lang, title]) { Rubbs::Common::Web::HTTP.get(url).body }
      #
      # Callers that miss the same key at once wait for the one computation and
      # share its value (or its error). When the computation raises and an
      # expired value of the key is still kept, that value is served instead.
      class Cache
        # One kept value: the value, when it expires (monotonic seconds) and its
        # size in bytes.
        Entry = Struct.new(:value, :expires, :bytes)

        # One running computation of a key, which the callers missing the same
        # key wait for: its value, its error, and whether it is over.
        Flight = Struct.new(:value, :error, :done) do
          # Returns the value, or raises the error.
          def outcome = error ? raise(error) : value
        end

        # Creates an empty cache.
        #
        # [ttl]         seconds a value stays fresh
        # [max_entries] the most values kept
        # [max_bytes]   the most bytes kept, all values together; +nil+ for no
        #               limit. A value bigger than this alone is not kept.
        # [size]        a callable giving the bytes of a value; by default its
        #               +bytesize+ (0 for a value without one)
        def initialize(ttl:, max_entries:, max_bytes: nil, size: nil)
          @ttl         = ttl
          @max_entries = max_entries
          @max_bytes   = max_bytes
          @size        = size || ->(value) { value.respond_to?(:bytesize) ? value.bytesize : 0 }
          @entries     = {}
          @flights     = {}
          @bytes       = 0
          @mu          = Mutex.new
          @landed      = ConditionVariable.new
        end

        # Returns the fresh value of +key+, or computes it with the block, keeps
        # it and returns it. Raises what the block raises, unless an expired
        # value of +key+ is kept: that one is returned then.
        def fetch(key, &)
          flight = @mu.synchronize do
            entry = fresh(key) and return entry.value
            if (running = @flights[key])
              @landed.wait(@mu) until running.done
              return running.outcome
            end
            @flights[key] = Flight.new
          end
          fly(key, flight, &)
          flight.outcome
        end

        # Computes the value of +key+ anew with the block, fresh or not, keeps
        # it and returns it. When the block raises, the value kept so far stays
        # and the error goes on: a background refresh never empties the cache.
        #
        #   CATALOG.refresh(:all) { repository.load }
        def refresh(key)
          value = yield
          @mu.synchronize { store(key, value) }
          value
        end

        # Forgets the value of +key+. Returns +nil+.
        def delete(key) = @mu.synchronize { drop(key) && nil }

        # Forgets every value. Returns +nil+.
        def clear
          @mu.synchronize do
            @entries.clear
            @bytes = 0
          end
          nil
        end

        # Returns the number of values kept, the expired ones included.
        def size = @mu.synchronize { @entries.size }

        private

        def fly(key, flight)
          flight.value = yield
          @mu.synchronize { store(key, flight.value) }
        rescue StandardError => e
          stale = @mu.synchronize { @entries[key] }
          flight.error = e unless stale
          flight.value = stale&.value
        ensure
          @mu.synchronize do
            flight.done = true
            @flights.delete(key)
            @landed.broadcast
          end
        end

        # The fresh entry of +key+, now the most recently used one.
        def fresh(key)
          entry = @entries[key]
          return unless entry && entry.expires > monotonic

          @entries[key] = @entries.delete(key)
        end

        def store(key, value)
          drop(key)
          size = @size.call(value)
          return if @max_bytes && size > @max_bytes

          @entries[key] = Entry.new(value, monotonic + @ttl, size)
          @bytes += size
          drop(@entries.first[0]) while @entries.size > @max_entries || (@max_bytes && @bytes > @max_bytes)
        end

        def drop(key)
          entry = @entries.delete(key) or return
          @bytes -= entry.bytes
          entry
        end

        def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
