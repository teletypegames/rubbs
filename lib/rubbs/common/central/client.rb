# frozen_string_literal: true

require 'json'

module Rubbs
  module Common
    module Central
      # A board's line to the Central: a signed POST (Rubbs::Common::Central::Signature)
      # to the Central's +url+ and a service's path, a JSON answer. Anything
      # that goes wrong — no answer, a slow one, no secret, a refused
      # signature, a broken answer — is one answer, UNAVAILABLE, and a +warn+
      # line in the log.
      #
      #   client = Rubbs::Common::Central::Client.new('http://ttg-gate-bbs:8090')
      #   client.ask('/wall', :recent, actor: actor, board: 'feedia-bbs')   # => { "result" => "ok", … }
      class Client
        # Seconds a request may take.
        TIMEOUT = 2

        # The Central's address (scheme, host and port, no path).
        attr_reader :url

        # A client of the Central at +url+, asking as the board +aud+ (this
        # board's technical name: Rubbs.config.log_tag unless given), each
        # request at most +timeout+ seconds.
        def initialize(url, aud: nil, timeout: TIMEOUT)
          @url     = url.to_s.chomp('/')
          @aud     = aud
          @timeout = timeout
        end

        # Asks the service at +path+ for +op+ as +actor+ (a
        # Rubbs::Common::Central::Actor, or +nil+ for an op that does not ask
        # who calls) with +fields+. Returns the answer, a Hash with String keys
        # and a +result+; UNAVAILABLE (a copy) when there is none.
        #
        # [timeout] seconds for this request, when not the client's
        def ask(path, op, actor: nil, timeout: nil, **fields)
          body   = JSON.generate({ op: op.to_s, aud: audience, ts: Time.now.to_i, actor: actor&.to_wire, **fields }.compact)
          answer = JSON.parse(post(path, body, timeout || @timeout).body.to_s)
          return answer if answer.is_a?(Hash) && answer.key?('result')

          Rubbs.log('central', 'no result', level: :warn, url: @url, path: path, answer: answer.to_s[0, 80])
          UNAVAILABLE.dup
        rescue Web::HTTP::Error, JSON::ParserError, Auth::Token::NoSecret => e
          Rubbs.log('central', e, level: :warn, url: @url, path: path)
          UNAVAILABLE.dup
        end

        # The board the requests are from.
        def audience = (@aud || Rubbs.config.log_tag).to_s

        private

        def post(path, body, timeout)
          Web::HTTP.post(
            "#{@url}#{path}",
            body:         body,
            headers:      { 'Content-Type' => 'application/json', Signature::HEADER => Signature.sign(path, body) },
            public_only:  false,
            read_timeout: timeout,
            deadline:     timeout
          )
        end
      end
    end
  end
end
