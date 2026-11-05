# frozen_string_literal: true

require 'json'
require 'webrick'

module Rubbs
  module Common
    module Auth
      # The accounts of a Rubbs::Common::Auth::Directory over HTTP, for the other boards
      # of the network (Rubbs::Common::Auth::Remote): one POST path, <tt>/auth</tt>, a
      # JSON request signed with the shared secret, a JSON answer. Run it
      # beside the telnet port on a network only the boards reach:
      #
      #   on_start { |bbs| Rubbs::Common::Auth::API.new(bbs.directory, port: 8090).start }
      #
      # A request is <tt>{ "op": …, "aud": the asking board, "ts": now, … }</tt>
      # with the header +X-RuBBS-Signature+, base64url(HMAC-SHA256) of the body
      # with a key of the secret (SIGNING). The +op+s and their fields:
      #
      # [log_in]          +name+, +password+, +caller_key+
      # [register]        +name+, +password+, +confirm+
      # [change_password] +name+, +password+, +fresh+, +caller_key+
      # [known]           +name+
      # [look_alike]      +name+
      #
      # The answer is <tt>{ "result": "ok", "token": … }</tt> (a token of the
      # account for the asking board) or <tt>{ "result": "wrong" }</tt> and
      # the like, the Symbols of Rubbs::Common::Auth::Directory; +known+ and +look_alike+
      # answer +true+ or +false+.
      class API
        # What the secret is stretched with for signing requests (HKDF info).
        SIGNING = 'rubbs-auth v1 api'
        # Seconds a request's +ts+ may be off.
        SKEW = 60
        # The largest request taken, in bytes.
        MAX_BODY = 4096

        # An API for +directory+ on +port+ of +host+.
        def initialize(directory, port:, host: '0.0.0.0')
          @directory = directory
          @server    = WEBrick::HTTPServer.new(
            Port:        port,
            BindAddress: host,
            Logger:      WEBrick::Log.new(File::NULL),
            AccessLog:   []
          )
          @server.mount_proc('/auth') { |request, response| respond(request, response) }
          @server.mount_proc('/health') { |_, response| response.body = 'ok' }
        end

        # The port it listens on (the one the system chose for port 0).
        def port = @server.config[:Port]

        # Serves in a Rubbs::Common::Board::Background thread. Returns the Thread.
        def start = Rubbs.background('auth api') { @server.start }

        # Stops serving.
        def stop = @server.shutdown

        # The answer to +body+ (the request's JSON) signed +signature+: a Hash.
        def answer(body, signature)
          return { error: 'signature' } unless signed?(body, signature)

          request = JSON.parse(body)
          return { error: 'stale' } unless (Time.now.to_i - request['ts'].to_i).abs <= SKEW

          operate(request)
        rescue JSON::ParserError
          { error: 'json' }
        end

        # The signature of +body+ with the first secret.
        def self.signature(body)
          key = Token.keys(SIGNING).first or raise Token::NoSecret
          Token.encode(Token.sign(key[:key], body))
        end

        private

        def respond(request, response)
          response['Content-Type'] = 'application/json'
          if request.request_method != 'POST' || request.body.to_s.bytesize > MAX_BODY
            response.status = 400
            return response.body = '{"error":"request"}'
          end

          result = answer(request.body.to_s, request['X-RuBBS-Signature'].to_s)
          response.status = result[:error] ? 403 : 200
          response.body = JSON.generate(result)
        end

        def signed?(body, signature)
          Token.keys(SIGNING).any? do |key|
            expected = Token.encode(Token.sign(key[:key], body))
            expected.bytesize == signature.bytesize && OpenSSL.fixed_length_secure_compare(expected, signature)
          end
        end

        def operate(request)
          name = request['name'].to_s
          case request['op']
          when 'known'      then { result: @directory.known?(name) }
          when 'look_alike' then { result: @directory.look_alike?(name) }
          else outcome(Auth.asked_by(request['aud']) { account_op(request, name) }, request['aud'])
          end
        end

        def account_op(request, name)
          caller_key = request['caller_key'].to_s
          case request['op']
          when 'log_in'   then @directory.log_in(name, request['password'].to_s, caller_key: caller_key)
          when 'register' then @directory.register(name, request['password'].to_s, request['confirm'].to_s)
          when 'change_password'
            @directory.change_password(name, request['password'].to_s, request['fresh'].to_s, caller_key: caller_key)
          else :unknown_op
          end
        end

        def outcome(result, aud)
          return { result: result.to_s } if result.is_a?(Symbol)

          { result: 'ok', token: Token.issue(result, aud: aud) }
        end
      end
    end
  end
end
