# frozen_string_literal: true

module BBS
  module Auth
    # Who the caller is, for an Application and a BBS::Petscii::Face
    # (their session's BBS::Auth::Identity): +identity+, +signed_in?+,
    # +role?+ and +log_out+. Each screen adds its own +log_in+.
    module Conveniences
      # The caller's BBS::Auth::Identity.
      def identity = @session.identity

      # Whether the caller is signed in.
      def signed_in? = identity.signed_in?

      # Whether the caller has any of +roles+.
      def role?(*roles) = identity.role?(*roles)

      # Forgets who the caller is: from now on a guest. Returns the guest
      # Identity.
      def log_out = (@session.identity = Identity.guest)

      private

      # The board's BBS::Auth::Setup, or +nil+.
      def auth_setup = BBS.config.auth

      # What the caller is told when the board has no login.
      def no_login = 'Nobody logs in on this board.'
    end
  end
end
