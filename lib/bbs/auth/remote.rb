# frozen_string_literal: true

require 'json'

module BBS
  module Auth
    # The accounts of another board (the home of the accounts) through its
    # BBS::Auth::API: the same answers as a BBS::Auth::Directory, so a board
    # uses either alike. An account comes back as a token for this board,
    # checked as any other (BBS::Auth::Token). When the home does not answer,
    # the answer is +:unavailable+.
    #
    #   BBS::Auth::Remote.new('http://ttg-gate-bbs:8090/auth')
    class Remote
      # Seconds a request may take.
      TIMEOUT = 10

      # The directory at +url+, asked as the board +aud+ (this board's
      # technical name).
      def initialize(url, aud: nil, timeout: TIMEOUT)
        @url     = url
        @aud     = aud
        @timeout = timeout
      end

      # See BBS::Auth::Directory#known?. +false+ when the home is away.
      def known?(name) = ask('known', name: name)['result'] == true

      # See BBS::Auth::Directory#look_alike?.
      def look_alike?(name) = ask('look_alike', name: name)['result'] == true

      # See BBS::Auth::Directory#log_in.
      def log_in(name, password, caller_key:)
        account('log_in', name: name, password: password, caller_key: caller_key)
      end

      # See BBS::Auth::Directory#register.
      def register(name, password, confirm = password)
        account('register', name: name, password: password, confirm: confirm)
      end

      # See BBS::Auth::Directory#change_password: +:ok+ or why not.
      def change_password(name, old, fresh, caller_key:)
        result = account('change_password', name: name, password: old, fresh: fresh, caller_key: caller_key)
        result.is_a?(Identity) ? :ok : result
      end

      private

      def account(op, **fields)
        answer = ask(op, **fields)
        return (answer['result'] || 'unavailable').to_sym unless answer['token']

        Token.verify(answer['token'], aud: audience).with(source: :login)
      rescue Token::Invalid => e
        BBS.log('auth', e, level: :warn)
        :unavailable
      end

      def ask(op, **fields)
        body = JSON.generate({ op: op, aud: audience, ts: Time.now.to_i, **fields })
        response = HTTP.post(
          @url,
          body:         body,
          headers:      { 'Content-Type' => 'application/json', 'X-RuBBS-Signature' => API.signature(body) },
          public_only:  false,
          read_timeout: @timeout,
          deadline:     @timeout
        )
        JSON.parse(response.body.to_s)
      rescue HTTP::Error, JSON::ParserError, Token::NoSecret => e
        BBS.log('auth', e, level: :warn, url: @url)
        {}
      end

      def audience = (@aud || BBS.config.log_tag).to_s
    end
  end
end
