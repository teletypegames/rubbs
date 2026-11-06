# frozen_string_literal: true

require 'openssl'

module Rubbs
  module Common
    module Central
      # How a request to the Central is signed: base64url(HMAC-SHA256) of
      # <tt>"<path>\n<body>"</tt> with a key stretched from the shared secret
      # (Rubbs::Common::Auth::Token.keys with SIGNING), in the header HEADER.
      # The path is signed too, so a request signed for one service is no good
      # on another. Several secrets (<tt>new,old</tt>) are tried while the
      # secret changes; the first one signs.
      #
      #   header = Signature.sign('/wall', body)
      #   Signature.valid?('/wall', body, header)   # => true
      module Signature
        # What the secret is stretched with (HKDF info).
        SIGNING = 'rubbs central v1'
        # The header the signature travels in.
        HEADER = 'X-RuBBS-Central'

        # The signature of +body+ for +path+ with the first secret. Raises
        # Rubbs::Common::Auth::Token::NoSecret without one.
        def self.sign(path, body)
          key = Auth::Token.keys(SIGNING).first or raise Auth::Token::NoSecret
          digest(key[:key], "#{path}\n#{body}")
        end

        # Whether +signature+ is one of +body+ for +path+ with any secret.
        def self.valid?(path, body, signature) = match?(SIGNING, "#{path}\n#{body}", signature)

        # base64url(HMAC-SHA256) of +text+ with +key+.
        def self.digest(key, text) = Auth::Token.encode(Auth::Token.sign(key, text))

        # Whether +signature+ is the digest of +text+ with a key of +use+.
        def self.match?(use, text, signature)
          signature = signature.to_s
          Auth::Token.keys(use).any? do |key|
            expected = digest(key[:key], text)
            expected.bytesize == signature.bytesize && OpenSSL.fixed_length_secure_compare(expected, signature)
          end
        end
        private_class_method :match?
      end
    end
  end
end
