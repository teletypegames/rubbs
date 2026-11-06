# frozen_string_literal: true

module Rubbs
  module Common
    module Central
      # A service of the Central as a board calls it: the same on the Central
      # (the request goes to its Rubbs::Common::Central::Server in the process)
      # and on any other board (a Rubbs::Common::Central::Client asks over
      # HTTP), so a board's code never knows which it has. Get one with
      # Rubbs.central.
      #
      #   wall = Rubbs.central(Wall)
      #   wall.call(:post, actor, text: 'Hello')   # => { "result" => "ok", "id" => 7 }
      #   wall.post(actor, text: 'Hello')          # the same, for an op the service declares
      #
      # Every answer is a Hash with String keys and a +result+; UNAVAILABLE
      # when the Central cannot be asked.
      class Proxy
        # The Service subclass it calls.
        attr_reader :service

        # A proxy of +service+ (a Service subclass) whose requests go through
        # +transport+, a callable given the path, the op, the actor and the
        # fields that returns the answer.
        def initialize(service, &transport)
          @service   = service
          @transport = transport
        end

        # A proxy of +service+ on the Central +server+ in this process.
        def self.local(service, server, aud: Rubbs.config.log_tag)
          new(service) do |path, op, actor, fields|
            request = { 'op' => op.to_s, 'aud' => aud.to_s, 'actor' => actor&.to_wire }
            server.dispatch(path, JSON.parse(JSON.generate(fields)).merge(request))
          end
        end

        # A proxy of +service+ through +client+, a Client of the Central.
        def self.remote(service, client)
          new(service) { |path, op, actor, fields| client.ask(path, op, actor: actor, **fields) }
        end

        # A proxy that always answers UNAVAILABLE: what a board without a
        # Central gets.
        def self.away(service) = new(service) { UNAVAILABLE.dup }

        # Asks for +op+ as +actor+ (a Rubbs::Common::Central::Actor, or +nil+)
        # with +fields+. Returns the answer.
        def call(op, actor = nil, **fields) = @transport.call(service.path, op, actor, fields)

        # An op the service declares, as a method: <tt>wall.post(actor, text: …)</tt>.
        def method_missing(name, actor = nil, **fields)
          return super unless service.ops.key?(name.to_s)

          call(name, actor, **fields)
        end

        # Whether +name+ is an op of the service (or a method of the proxy).
        def respond_to_missing?(name, include_private = false) = service.ops.key?(name.to_s) || super
      end
    end
  end
end
