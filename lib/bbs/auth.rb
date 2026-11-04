# frozen_string_literal: true

require_relative 'auth/identity'
require_relative 'auth/names'
require_relative 'auth/password'
require_relative 'auth/guard'
require_relative 'auth/token'
require_relative 'auth/accounts'
require_relative 'auth/directory'
require_relative 'auth/api'
require_relative 'auth/remote'
require_relative 'auth/login'
require_relative 'auth/conveniences'

module BBS
  # Who is on the line, the same on every board of a network: accounts with
  # roles kept by one board (BBS::Auth::Directory and its BBS::Auth::API),
  # asked by the others (BBS::Auth::Remote), and a call handed on from one
  # board to another with its identity in a signed, single-use token
  # (BBS::Auth::Token, sent as RUBBS_AUTH_KEY by a forwarding
  # BBS::Gateway). The secret every board shares is +RUBBS_AUTH_SECRET+.
  #
  # A board declares it in BBS.board:
  #
  #   auth BBS::Auth::Remote.new('http://home-bbs:8090/auth'), login: :menu
  #   auth(login: :call) { |board| board.directory }   # the home of the accounts
  #
  # and reads it with +identity+, +signed_in?+ and <tt>role?(:sysop)</tt> in
  # an Application, a BBS::Petscii::Face and a flow.
  module Auth
    # How a board logs its callers in: its +directory+ (a
    # BBS::Auth::Directory or Remote), +login+ (+:call+: asked at the start
    # of a call, before the face; +:menu+: from a menu item; +:both+) and
    # +guests+ (whether a caller without an account comes in at a +:call+
    # login).
    Setup = Data.define(:directory, :login, :guests) do
      # Whether the call starts with a login.
      def at_call? = %i[call both].include?(login)

      # Whether the faces offer a login item.
      def in_menu? = %i[menu both].include?(login)
    end

    # The modes of Setup#login.
    LOGINS = %i[call menu both].freeze

    # The Identity of the caller on +session+ when the call came: the one a
    # neighbouring board handed on in RUBBS_AUTH_KEY (BBS::Telnet::Forwarded,
    # checked by Token.verify for this board), else a guest. A key that is
    # not good is logged and the caller is a guest.
    def self.from_line(session)
      key = session.respond_to?(:forwarded) ? session.forwarded['RUBBS_AUTH_KEY'] : nil
      return Identity.guest unless key

      Token.verify(key, aud: BBS.config.log_tag)
    rescue Token::Invalid => e
      BBS.log('auth', e, level: :warn, via: session.via.to_s)
      Identity.guest
    end
  end
end
