# frozen_string_literal: true

module BBS
  module Auth
    # Wrong passwords counted by the name tried and by the line they came
    # from (BBS::RateLimit): past either limit the name or the line waits out
    # the window before a password is checked for it again. With a +store+
    # (a Sequel::Database) the counts outlive a restart.
    class Guard
      # Seconds a wrong password counts.
      WINDOW = 900

      # A guard of +per_name+ wrong passwords for a name and +per_caller+ for
      # a line in +window+ seconds.
      def initialize(store: nil, per_name: 10, per_caller: 6, window: WINDOW)
        @names   = RateLimit.new(limit: per_name, per: window, store: store, name: store && 'auth by name')
        @callers = RateLimit.new(limit: per_caller, per: window, store: store, name: store && 'auth by line')
      end

      # Seconds until +name+ from +caller_key+ may try again; 0 when now.
      def wait(name, caller_key) = [@names.wait(Names.key(name)), @callers.wait(caller_key.to_s)].max

      # Whether +name+ from +caller_key+ has to wait.
      def locked?(name, caller_key) = wait(name, caller_key).positive?

      # Counts a wrong password for +name+ from +caller_key+.
      def failed(name, caller_key)
        @names.record(Names.key(name))
        @callers.record(caller_key.to_s)
      end
    end
  end
end
