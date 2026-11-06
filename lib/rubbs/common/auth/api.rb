# frozen_string_literal: true

module Rubbs
  module Common
    module Auth
      # The accounts of a Rubbs::Common::Auth::Directory over HTTP, alone: a
      # Rubbs::Common::Central::Server with only Rubbs::Common::Auth::Service on
      # <tt>/auth</tt>. A board that keeps the accounts declares the Central
      # instead (Rubbs.board's <tt>central serve:</tt>), which serves them
      # with its other services; this is for a board that serves only the
      # accounts:
      #
      #   on_start { |bbs| Rubbs::Common::Auth::API.new(bbs.directory, port: 8090).start }
      class API
        # A Central of the accounts of +directory+ on +port+ of +host+.
        def initialize(directory, port:, host: '0.0.0.0')
          @server = Central::Server.new(services: [Service], accounts: directory, port: port, host: host)
        end

        # The port it listens on (the one the system chose for port 0).
        def port = @server.port

        # Serves in a Rubbs::Common::Board::Background thread. Returns the Thread.
        def start = @server.start

        # Stops serving.
        def stop = @server.stop

        # The answer to +body+ (the request's JSON) for <tt>/auth</tt> signed
        # +signature+ (Rubbs::Common::Central::Signature): a Hash.
        def answer(body, signature) = @server.answer('/auth', body, signature)
      end
    end
  end
end
