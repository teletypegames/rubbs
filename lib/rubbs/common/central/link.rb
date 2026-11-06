# frozen_string_literal: true

module Rubbs
  module Common
    module Central
      # A board's tie to the Central (Rubbs.config.central, set by Rubbs.board's
      # +central+): on the Central its Rubbs::Common::Central::Server, on any
      # other board a Rubbs::Common::Central::Client. Hands out the services as
      # Rubbs::Common::Central::Proxy objects (#proxy, Rubbs.central).
      class Link
        # The Server (on the Central) or +nil+.
        attr_reader :server

        # The Client (on another board) or +nil+.
        attr_reader :client

        # A link to the Central: +server+ on the Central itself, +client+ on
        # another board.
        def initialize(server: nil, client: nil)
          @server = server
          @client = client
        end

        # Whether this board is the Central.
        def central? = !@server.nil?

        # The +service+ (a Service subclass) as a Proxy: local on the Central,
        # remote elsewhere.
        def proxy(service)
          return Proxy.local(service, @server) if @server
          return Proxy.remote(service, @client) if @client

          Proxy.away(service)
        end
      end
    end
  end
end
