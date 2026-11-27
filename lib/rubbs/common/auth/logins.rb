# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      # What a board does when a caller signs in on a call: blocks registered
      # with Logins.on_login, run once for every account signed in on the
      # call, as soon as the call has its face (a caller handed on signed in
      # by another board is signed in before the terminal question). A block
      # leaves the caller a notice there (Rubbs::Common::Line::Notices), and
      # the screens show it.
      #
      #   Rubbs::Common::Auth::Logins.on_login do |session|
      #     session.notice('You have mail.', title: 'Mail') if mail_for?(session.identity)
      #   end
      #
      # The blocks run in the caller's thread, so they keep it short; an
      # error of one is logged, the others run.
      module Logins
        # Registers +block+, called with the session at every sign-in.
        # Returns the block.
        def self.on_login(&block)
          raise ArgumentError, 'on_login needs a block' unless block

          hooks << block
          block
        end

        # The registered blocks.
        def self.hooks = @hooks ||= []

        # Forgets the registered blocks (a test's teardown).
        def self.clear = @hooks = []

        # Runs the blocks for +session+ when it has a face and a signed-in
        # account it did not run them for yet. Returns the blocks it ran, or
        # +nil+.
        def self.signed_in(session)
          id = session.face && session.identity.signed_in? ? session.identity.id : nil
          return nil if id.nil? || session.login_seen == id

          session.login_seen = id
          hooks.each { |hook| run(hook, session) }
        end

        # Runs +hook+ for +session+, logging an error instead of raising it.
        def self.run(hook, session)
          hook.call(session)
        rescue StandardError => e
          Rubbs.log('login', e, session: session.session_id)
        end
      end
    end
  end
end
