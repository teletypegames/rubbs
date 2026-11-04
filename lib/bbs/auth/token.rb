# frozen_string_literal: true

require 'json'
require 'openssl'
require 'securerandom'

module BBS
  module Auth
    # The key a board hands a caller's identity on with: a short-lived,
    # single-use token signed with the secret every board of the network
    # shares (BBS.config.auth_secrets, the +RUBBS_AUTH_SECRET+ variable):
    #
    #   v1.<kid>.<payload>.<signature>
    #
    #   payload   = base64url(JSON: sub, id, roles, iss, aud, iat, exp, jti)
    #   signature = base64url(HMAC-SHA256(HKDF(secret), "v1.<kid>.<payload>"))
    #
    # The payload is signed, not hidden: a name and roles are no secret,
    # their authenticity is. A token is for one board (+aud+), lives TTL
    # seconds and is taken once (+jti+), so one caught on the line is of no
    # use later or elsewhere. Several secrets (<tt>new,old</tt>) let the
    # secret change: the first signs, any of them is accepted, told apart by
    # +kid+.
    #
    #   key = BBS::Auth::Token.issue(identity, aud: 'ttg-blog-bbs')
    #   BBS::Auth::Token.verify(key, aud: 'ttg-blog-bbs')   # => the Identity (source :token)
    module Token
      # The version, the first field.
      VERSION = 'v1'
      # Seconds a token lives.
      TTL = 60
      # Seconds the clocks of two boards may differ by.
      LEEWAY = 30
      # The longest token taken.
      MAX_BYTES = 600
      # What the secret is stretched with for signing (HKDF info).
      SIGNING = 'rubbs-auth v1 sign'

      # A token that is not good; its subclasses say why.
      class Invalid < StandardError; end
      # Not a token of this version.
      class Malformed < Invalid; end
      # Signed with no secret of this board, or tampered with.
      class BadSignature < Invalid; end
      # For another board.
      class WrongAudience < Invalid; end
      # Out of its time.
      class Expired < Invalid; end
      # Taken before.
      class Replayed < Invalid; end
      # No secret is set (RUBBS_AUTH_SECRET), so nothing can be signed or checked.
      class NoSecret < Invalid; end

      @seen  = {}
      @mutex = Mutex.new

      class << self
        # A token of +identity+ for the board +aud+ (its technical name),
        # issued by +iss+ (this board's). Raises NoSecret.
        def issue(identity, aud:, iss: BBS.config.log_tag, ttl: TTL, now: Time.now)
          key = keys.first or raise NoSecret
          claims = {
            sub:   identity.name,
            id:    identity.id,
            roles: identity.roles,
            iss:   iss.to_s,
            aud:   aud.to_s,
            iat:   now.to_i,
            exp:   now.to_i + ttl,
            jti:   SecureRandom.hex(8)
          }
          body = "#{VERSION}.#{key[:kid]}.#{encode(JSON.generate(claims))}"
          "#{body}.#{encode(sign(key[:key], body))}"
        end

        # The Identity of +token+ if it is good for the board +aud+, else
        # raises an Invalid (Malformed, BadSignature, WrongAudience, Expired,
        # Replayed, NoSecret). A good token is remembered and refused when
        # it comes again.
        def verify(token, aud:, now: Time.now)
          claims = claims(token.to_s)
          raise WrongAudience, "for #{claims['aud']}" unless claims['aud'] == aud.to_s

          remember(claims['jti'].to_s, in_time(claims, now.to_i), now.to_i)
          Identity.new(id: claims['id'], name: claims['sub'], roles: claims['roles'], source: :token)
        end

        # The keys of BBS.config.auth_secrets for +use+ (an HKDF info: SIGNING
        # for tokens, BBS::Auth::API::SIGNING for its requests):
        # <tt>{ kid:, key: }</tt> each, the first the one that signs.
        def keys(use = SIGNING)
          Array(BBS.config.auth_secrets).map do |secret|
            key = OpenSSL::KDF.hkdf(secret, salt: '', info: use, length: 32, hash: 'SHA256')
            { kid: OpenSSL::Digest::SHA256.hexdigest(key)[0, 8], key: key }
          end
        end

        # Forgets the tokens taken so far (a test's fresh start).
        def forget! = @mutex.synchronize { @seen.clear }

        private

        def claims(token)
          raise Malformed, 'too long' if token.bytesize > MAX_BYTES

          version, kid, payload, signature = token.split('.')
          raise Malformed unless version == VERSION && signature

          check_signature(kid, "#{version}.#{kid}.#{payload}", signature)
          JSON.parse(decode(payload))
        rescue JSON::ParserError, ArgumentError
          raise Malformed
        end

        def check_signature(kid, body, signature)
          key = keys.find { |k| k[:kid] == kid } or raise(keys.empty? ? NoSecret : BadSignature)
          expected = encode(sign(key[:key], body))
          return if expected.bytesize == signature.bytesize && OpenSSL.fixed_length_secure_compare(expected, signature)

          raise BadSignature
        end

        # The time until which +claims+ are good; raises Expired when +now+ is
        # out of it.
        def in_time(claims, now)
          last = claims['exp'].to_i + LEEWAY
          raise Expired unless now.between?(claims['iat'].to_i - LEEWAY, last)

          last
        end

        def remember(jti, until_time, now)
          @mutex.synchronize do
            @seen.delete_if { |_, time| time < now }
            raise Replayed if @seen.key?(jti)

            @seen[jti] = until_time
          end
        end
      end

      # The HMAC-SHA256 of +text+ with +key+, bytes.
      def self.sign(key, text) = OpenSSL::HMAC.digest('SHA256', key, text)

      # +bytes+ in base64url without padding.
      def self.encode(bytes) = [bytes].pack('m0').tr('+/', '-_').delete('=')

      # The bytes of base64url +text+ (padding optional).
      def self.decode(text) = (text + ('=' * ((4 - (text.length % 4)) % 4))).tr('-_', '+/').unpack1('m0')
    end
  end
end
