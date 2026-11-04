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
require_relative 'auth/profile'

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
    # The thread-local key of the board a request of BBS::Auth::API came
    # from, the +asker+ of the events it causes.
    ASKER = :bbs_auth_asker

    # Logs an auth +event+ (a Symbol: +:login+, +:login_failed+, +:locked+,
    # +:register+, +:register_refused+, +:password+, +:grant+, +:revoke+,
    # +:handed_on+, +:token_refused+, +:logout+) as one +auth+ line with
    # +event+, +asker+ (the board the caller is on: this one, or the one
    # that asked the API) and +facts+, for a log pipeline to count. Returns
    # +nil+.
    def self.event(event, level: :info, **facts)
      asker = Thread.current[ASKER] || BBS.config.log_tag
      BBS.log('auth', event.to_s, level: level, event: event.to_s, asker: asker.to_s, **facts)
    end

    # Runs the block with +board+ as the asker of the events it logs.
    def self.asked_by(board)
      before = Thread.current[ASKER]
      Thread.current[ASKER] = board
      yield
    ensure
      Thread.current[ASKER] = before
    end

    # The Identity of the caller on +session+ when the call came: the one a
    # neighbouring board handed on in RUBBS_AUTH_KEY (BBS::Telnet::Forwarded,
    # checked by Token.verify for this board), else a guest. A key that is
    # not good is logged and the caller is a guest.
    def self.from_line(session)
      key = session.respond_to?(:forwarded) ? session.forwarded['RUBBS_AUTH_KEY'] : nil
      key ? handed_on(key, session.via.to_s) : Identity.guest
    end

    # The Identity of the RUBBS_AUTH_KEY +key+ a call came with through the
    # board +via+, or a guest when it is not good (both logged).
    def self.handed_on(key, via)
      identity = Token.verify(key, aud: BBS.config.log_tag)
      event(:handed_on, name: identity.name, via: via)
      identity
    rescue Token::Invalid => e
      event(:token_refused, level: :warn, reason: e.class.name.split('::').last, via: via)
      Identity.guest
    end
  end
end
