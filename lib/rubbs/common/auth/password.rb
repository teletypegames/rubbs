# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module Rubbs
  module Common
    module Auth
      # A password as an account keeps it: PBKDF2-SHA256 with a random salt,
      # in one self-describing String,
      #
      #   pbkdf2-sha256$200000$<salt, base64>$<hash, base64>
      #
      # so a digest of other iterations (an older board's) is still checked,
      # and #rehash? says when to store it anew. At most SLOTS derivations run
      # at once: PBKDF2 holds the interpreter lock, and a flood of guesses
      # must not stall every other caller's screen.
      module Password
        # The kind of digest, its first field.
        KIND = 'pbkdf2-sha256'
        # The iterations of a new digest.
        ITERATIONS = 200_000
        # Derivations at once; more wait up to WAIT seconds, then Busy.
        SLOTS = 2
        # Seconds a derivation waits for a slot.
        WAIT = 5

        # Raised when no slot came free in WAIT seconds.
        class Busy < StandardError
          # The error with its message.
          def initialize(message = 'too many passwords checked at once') = super
        end

        @slots = Thread::SizedQueue.new(SLOTS)

        class << self
          # The digest of +password+ with a new salt (or +salt+, bytes).
          # Raises Busy.
          def digest(password, salt: SecureRandom.bytes(16), iterations: ITERATIONS)
            hash = derive(password, salt, iterations)
            [KIND, iterations, [salt].pack('m0'), [hash].pack('m0')].join('$')
          end

          # Whether +password+ is the one of +stored+ (a digest). A +nil+
          # +stored+ (no such account) still costs one derivation, so the time
          # taken does not tell a wrong name from a wrong password. Raises
          # Busy.
          def match?(stored, password)
            kind, iterations, salt, hash = (stored || nobody).split('$')
            return false unless kind == KIND && hash

            fresh = [derive(password, salt.unpack1('m0'), iterations.to_i)].pack('m0')
            OpenSSL.fixed_length_secure_compare(fresh, hash) && !stored.nil?
          rescue ArgumentError
            false
          end

          # Whether +stored+ was made with fewer iterations than ITERATIONS.
          def rehash?(stored) = stored.to_s.split('$')[1].to_i < ITERATIONS

          # The digest of a salt and hash kept as hex with +iterations+, the
          # way a board of rubbs 2.4 or older might have kept them.
          def from_hex(salt_hex, digest_hex, iterations:)
            [KIND, iterations, [[salt_hex].pack('H*')].pack('m0'), [[digest_hex].pack('H*')].pack('m0')].join('$')
          end

          private

          def nobody = @nobody ||= digest('')

          def derive(password, salt, iterations)
            @slots.push(true, timeout: WAIT) or raise Busy
            begin
              OpenSSL::KDF.pbkdf2_hmac(password.to_s, salt: salt, iterations: iterations, length: 32, hash: 'sha256')
            ensure
              @slots.pop
            end
          end
        end
      end
    end
  end
end
