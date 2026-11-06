# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      # The accounts of another board (the Central) through its
      # Rubbs::Common::Auth::Service: the same answers as a Rubbs::Common::Auth::Directory, so a board
      # uses either alike. An account comes back as a token for this board,
      # checked as any other (Rubbs::Common::Auth::Token). When the Central does not answer,
      # the answer is +:unavailable+.
      #
      #   Rubbs::Common::Auth::Remote.new('http://ttg-gate-bbs:8090')          # the Central's address
      #   Rubbs::Common::Auth::Remote.new(client: Rubbs.config.central.client)  # its Central::Client
      #
      # An address that ends in <tt>/auth</tt> (the form before the Central)
      # is taken without it.
      class Remote
        # Seconds a request may take.
        TIMEOUT = 10

        # The Central::Client it asks.
        attr_reader :client

        # The accounts of the Central at +url+ (or through +client+, a
        # Rubbs::Common::Central::Client), asked as the board +aud+ (this
        # board's technical name), each request at most +timeout+ seconds.
        def initialize(url = nil, aud: nil, timeout: TIMEOUT, client: nil)
          raise ArgumentError, 'an address or a client' unless url || client

          @client  = client || Central::Client.new(url.to_s.chomp('/').delete_suffix('/auth'), aud: aud)
          @timeout = timeout
        end

        # See Rubbs::Common::Auth::Directory#known?; +false+ when the Central is away.
        def known?(name) = account_state(name) == :known

        # Whether +name+ has an account: +:known+, +:unknown+, or +:unavailable+
        # when the Central did not answer, so a board can tell "no such account"
        # from "cannot say" and keep a name it cannot check from coming in as a
        # guest.
        def account_state(name)
          answer = ask('known', name: name)['result']
          return :unavailable unless [true, false].include?(answer)

          answer ? :known : :unknown
        end

        # See Rubbs::Common::Auth::Directory#look_alike?.
        def look_alike?(name) = ask('look_alike', name: name)['result'] == true

        # See Rubbs::Common::Auth::Directory#log_in.
        def log_in(name, password, caller_key:)
          account('log_in', name: name, password: password, caller_key: caller_key)
        end

        # See Rubbs::Common::Auth::Directory#register.
        def register(name, password, confirm = password)
          account('register', name: name, password: password, confirm: confirm)
        end

        # See Rubbs::Common::Auth::Directory#change_password: +:ok+ or why not.
        def change_password(name, old, fresh, caller_key:)
          result = account('change_password', name: name, password: old, fresh: fresh, caller_key: caller_key)
          result.is_a?(Identity) ? :ok : result
        end

        private

        def account(op, **fields)
          answer = ask(op, **fields)
          return (answer['result'] || 'unavailable').to_sym unless answer['token']

          Token.verify(answer['token'], aud: @client.audience).with(source: :login)
        rescue Token::Invalid => e
          Rubbs.log('auth', e, level: :warn)
          :unavailable
        end

        def ask(op, **fields) = @client.ask('/auth', op, timeout: @timeout, **fields)
      end
    end
  end
end
