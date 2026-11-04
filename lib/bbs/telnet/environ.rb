# frozen_string_literal: true

module BBS
  module Telnet
    # The variables of telnet NEW-ENVIRON (RFC 1572), the telnet relative of
    # HTTP's headers: name-value pairs a client sends the server. rubbs uses
    # them between its own boards: a BBS::Gateway with <tt>forward: true</tt>
    # tells the board it calls who is really calling (FORWARDED), and that
    # board believes it only from a neighbour (BBS::Telnet::Forwarded).
    #
    #   BBS::Telnet::Environ.info('BBS_FACE' => 'petscii')   # => the bytes of one IAC SB … IAC SE
    #   BBS::Telnet::Environ.parse([39, 2, 3, *'BBS_FACE'.bytes, 1, *'petscii'.bytes])
    #   # => { 'BBS_FACE' => 'petscii' }
    module Environ
      include Codes

      # Subnegotiation: the variables follow, asked for.
      IS    = 0
      # Subnegotiation: the server asks for variables.
      SEND  = 1
      # Subnegotiation: the variables follow, unasked (or changed).
      INFO  = 2
      # A well-known variable's name follows.
      VAR   = 0
      # The value of the variable before it follows.
      VALUE = 1
      # The next byte is taken as it is, even when it is one of these codes.
      ESC   = 2
      # A variable of the client's own naming follows.
      USERVAR = 3
      # The bytes that need an ESC before them inside a name or a value.
      SPECIAL = [VAR, VALUE, ESC, USERVAR].freeze
      # The most variables kept from one line.
      MAX_VARIABLES = 16
      # The variables a forwarding BBS::Gateway sends: the face the caller
      # picked on the first board (+modern+ or +petscii+), the caller's own
      # IP address, the name of the board the call came through, and a
      # signed-in caller's identity (a BBS::Auth::Token).
      FORWARDED = %w[BBS_FACE BBS_CLIENT_IP BBS_VIA RUBBS_AUTH_KEY].freeze

      # The variables of a NEW-ENVIRON subnegotiation, +bytes+ an Array of
      # Integer as BBS::Telnet::Parser gives it (the option first): a Hash of
      # name => value (a variable without a value has an empty one). Only
      # IS and INFO carry variables; anything else is an empty Hash.
      def self.parse(bytes)
        return {} unless bytes[0] == NEW_ENVIRON_OPT && [IS, INFO].include?(bytes[1])

        pairs(unescape(bytes[2..]))
      end

      # The bytes that send +variables+ (a Hash of name => value, Strings of
      # ASCII) as USERVARs, unasked: one INFO subnegotiation a variable, so
      # each stays short. A binary String.
      def self.info(variables)
        variables.map do |name, value|
          [IAC, SB, NEW_ENVIRON_OPT, INFO, USERVAR, *escape(name), VALUE, *escape(value), IAC, SE].pack('C*')
        end.join
      end

      # The bytes of +text+ with an ESC before every code byte, a doubled
      # IAC for a 255.
      def self.escape(text)
        text.to_s.bytes.flat_map { |b| SPECIAL.include?(b) ? [ESC, b] : [b] }.flat_map { |b| b == IAC ? [IAC, IAC] : [b] }
      end
      private_class_method :escape

      # +bytes+ as tokens: <tt>[:code, byte]</tt> for a code, an Integer for
      # a byte of a name or a value.
      def self.unescape(bytes)
        tokens = []
        escaped = false
        bytes.each do |b|
          if escaped then tokens << b
          elsif b == ESC then escaped = true; next
          else tokens << (SPECIAL.include?(b) ? [:code, b] : b)
          end
          escaped = false
        end
        tokens
      end
      private_class_method :unescape

      # The name => value pairs of +tokens+.
      def self.pairs(tokens)
        vars = {}
        name = nil
        tokens.slice_before { |t| t.is_a?(Array) }.each do |(code, *rest)|
          next unless code.is_a?(Array)

          text = rest.pack('C*').force_encoding(Encoding::UTF_8).scrub
          if [VAR, USERVAR].include?(code[1]) then vars[name = text] = ''
          elsif name then vars[name] = text
          end
          break if vars.size >= MAX_VARIABLES
        end
        vars
      end
      private_class_method :pairs
    end
  end
end
