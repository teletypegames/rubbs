# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      # Who the caller is, for an Application and a Rubbs::Petscii::Face
      # (their session's Rubbs::Common::Auth::Identity): +identity+, +signed_in?+,
      # +role?+ and +log_out+. Each screen adds its own +log_in+.
      module Conveniences
        # The caller's Rubbs::Common::Auth::Identity.
        def identity = @session.identity

        # Whether the caller is signed in.
        def signed_in? = identity.signed_in?

        # Whether the caller has any of +roles+.
        def role?(*roles) = identity.role?(*roles)

        # Forgets who the caller is: from now on a guest. Returns the guest
        # Identity.
        def log_out
          Auth.event(:logout, name: identity.name) if signed_in?
          @session.identity = Identity.guest
        end

        private

        # The board's Rubbs::Common::Auth::Setup, or +nil+.
        def auth_setup = Rubbs.config.auth

        # What the caller is told when the board has no login.
        def no_login = 'Nobody logs in on this board.'
      end
    end
  end
end
