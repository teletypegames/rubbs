# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      # The part of Rubbs::Common::Board::BoardDefinition that ties a board to
      # the Central (Rubbs::Common::Central): the +central+ declaration and
      # how Rubbs.board applies it (a Rubbs::Common::Central::Link in
      # Rubbs.config.central), and the accounts of +auth+ (the Central's
      # when it names none).
      module CentralWiring
        # The board's tie to the Central (Rubbs::Common::Central), where the
        # network's shared data lives.
        #
        # On any other board, the Central's address (or a
        # Rubbs::Common::Central::Client): #auth without a directory asks its
        # accounts, and Rubbs.central its services.
        #
        # On the Central itself, +serve+: the port of its
        # Rubbs::Common::Central::Server (a number, or a block given the domain
        # object at boot; 0 or +nil+: no port, the board's own calls only),
        # with +services+ (Rubbs::Common::Central::Service subclasses; the
        # accounts' Rubbs::Common::Auth::Service comes by itself when #auth has
        # a Rubbs::Common::Auth::Directory) and their databases in +data+ (the
        # board's data folder, against the domain's root).
        #
        #   central 'http://ttg-gate-bbs:8090'                        # any board
        #   central serve: 8090, services: [Feedback, Wall]           # the Central
        def central(address = nil, serve: nil, services: [], data: 'data', host: '0.0.0.0')
          raise ArgumentError, 'central: an address or serve:, not both' if address && serve

          @central = { address: address, serve: serve, services: services, data: data, host: host }
        end

        # Sends the events of the board's signed-in callers to the badges of
        # the Central (a Rubbs::Common::Badges::Reporter in Rubbs.config.badges):
        # the board's name in the badges is +board+ (its technical name
        # without +-bbs+ by default), the one its file of badges
        # (Rubbs.badges) declares.
        #
        #   badges :hackercave
        def badges(board = nil) = (@badges = (board || @slug.delete_suffix('-bbs')).to_s)

        private

        def configure_badges
          Rubbs.config.badges = @badges ? Badges::Reporter.new(Rubbs.central(Badges::Service), board: @badges) : nil
        end

        def configure_auth
          return Rubbs.config.auth = nil unless @auth

          directory, login, guests = @auth
          directory = directory.call(@board) if directory.respond_to?(:call)
          directory ||= central_accounts
          Rubbs.config.auth = Auth::Setup.new(directory: directory, login: login, guests: guests)
        end

        def central_accounts
          client = Rubbs.config.central&.client or raise ArgumentError, 'auth without a directory needs a central address'

          Auth::Remote.new(client: client)
        end

        def configure_central_client
          address = @central&.fetch(:address)
          Rubbs.config.central = case address
                                 when nil then nil
                                 when Central::Client then Central::Link.new(client: address)
                                 else Central::Link.new(client: Central::Client.new(address))
                                 end
        end

        def configure_central_server
          return unless @central && !@central[:address]

          server = Central::Server.new(**central_server_options)
          Rubbs.config.central = Central::Link.new(server: server)
          server.start if server.port
        end

        def central_server_options
          accounts = Rubbs.config.auth&.directory
          accounts = nil unless accounts.is_a?(Auth::Directory)
          services = [*(accounts ? [Auth::Service] : []), *@central[:services]]
          root     = @domain.respond_to?(:root) ? @domain.root : Dir.pwd
          {
            services: services,
            accounts: accounts,
            port:     central_port,
            host:     @central[:host],
            data:     File.expand_path(@central[:data], root)
          }
        end

        def central_port
          port = @central[:serve]
          port = port.call(@board) if port.respond_to?(:call)
          return nil if port.nil? || port.to_i.zero?
          return port.to_i unless Rubbs.config.auth_secrets.empty?

          Rubbs.log('central', 'no RUBBS_AUTH_SECRET: the Central serves only this board', level: :warn)
          nil
        end
      end
    end
  end
end
