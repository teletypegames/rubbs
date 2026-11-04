# frozen_string_literal: true

module BBS
  module Auth
    # A login on a line, asked with two callables so any screen can show it:
    # +ask+ (a label and <tt>mask:</tt>, returning the answer or +nil+ when
    # the caller gave none) and +tell+ (a line for the caller). A flow, a
    # BBS::Petscii::Face and a board's own screens use it alike.
    #
    #   login = BBS::Auth::Login.new(setup, session, ask: ->(label, mask: nil) { … }, tell: ->(text) { … })
    #   login.run        # => the Identity now on the session, or nil
    class Login
      # Passwords asked for one name in one go.
      TRIES = 3
      # What the caller is told for each answer of the directory.
      WORDS = {
        wrong:       'Wrong name or password.',
        locked:      'Too many wrong passwords. Try again later.',
        busy:        'The board is busy. Try again in a moment.',
        unavailable: 'Logging in is not possible right now. Try again later.'
      }.freeze

      # A login with +setup+ (a Setup) for the caller on +session+.
      def initialize(setup, session, ask:, tell:)
        @setup   = setup
        @session = session
        @ask     = ask
        @tell    = tell
      end

      # Asks a name (or takes +name+) and its password, up to TRIES times.
      # On success the Identity is the session's and is returned; else +nil+.
      def run(name = nil)
        name ||= @ask.call('name')
        return nil if name.to_s.strip.empty?

        TRIES.times do
          result = attempt(name.strip) or return nil
          return @session.identity = result if result.is_a?(Identity)

          @tell.call(WORDS.fetch(result, WORDS[:wrong]))
          return nil unless result == :wrong
        end
        nil
      end

      # The login at the start of a call (Setup#at_call?): a name, then for an
      # account its password; with +guests+ an empty name or one without an
      # account comes in as a guest (named, if a name was given). Returns
      # +:ok+ (signed in, or a guest let in) or +:halt+ (the call ends).
      def at_call
        return :ok if @session.identity.signed_in?

        name = @ask.call(@setup.guests ? 'name (Return: guest)' : 'name').to_s.strip
        return guest(nil) if name.empty?
        return guest(name) unless @setup.directory.known?(name)

        run(name) ? :ok : :halt
      end

      private

      def attempt(name)
        password = @ask.call('password', mask: '*') or return nil
        @setup.directory.log_in(name, password, caller_key: @session.caller_key)
      end

      def guest(name)
        return :halt unless @setup.guests

        @session.identity = Identity.guest(Names.clean(name.to_s))
        :ok
      end
    end
  end
end
