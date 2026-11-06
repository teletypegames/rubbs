# frozen_string_literal: true

require_relative 'central/signature'
require_relative 'central/actor'
require_relative 'central/service'
require_relative 'central/client'
require_relative 'central/server'
require_relative 'central/proxy'
require_relative 'central/link'

module Rubbs
  module Common
    # The data a network of boards shares, kept by one of them (the Central)
    # and asked by the others: the accounts (Rubbs::Common::Auth::Service) and
    # whatever services a network adds (a feedback box, a wall).
    #
    # One mechanism for all of them:
    #
    # - Rubbs::Common::Central::Server on the Central: one port, a path a
    #   service, every request signed (Rubbs::Common::Central::Signature) and
    #   its caller checked once (Rubbs::Common::Central::Actor);
    # - Rubbs::Common::Central::Client on the other boards: one signed POST,
    #   one way to fail (+unavailable+);
    # - Rubbs::Common::Central::Service: what a service declares (its path,
    #   database and ops); a board calls it through a
    #   Rubbs::Common::Central::Proxy, the same here and there.
    #
    # A board declares it in Rubbs.board:
    #
    #   central serve: 8090, services: [Feedback::Service]       # the Central
    #   central 'http://gate-bbs:8090'                           # any other board
    #
    # and calls a service with <tt>Rubbs.central(:feedback)</tt>. The secret
    # is the one of Rubbs::Common::Auth::Token, +RUBBS_AUTH_SECRET+.
    module Central
      # What a service's answer is when the Central cannot be asked.
      UNAVAILABLE = { 'result' => 'unavailable' }.freeze

      # The words of a request that are not a parameter of an op.
      RESERVED = %w[op aud ts actor].freeze
    end
  end
end
