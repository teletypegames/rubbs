# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'webrick'

module Rubbs
  module Common
    module Central
      # The Central's side: its services (Rubbs::Common::Central::Service
      # subclasses) on one port, a path each, for the other boards of the
      # network. Run it beside the telnet port on a network only the boards
      # reach (Rubbs.board's +central serve:+ does):
      #
      #   server = Rubbs::Common::Central::Server.new(services: [Auth::Service, Wall], accounts: directory, port: 8090)
      #   server.start
      #
      # Every request is a POST of JSON, <tt>{ "op", "aud", "ts", "actor", … }</tt>,
      # signed (Rubbs::Common::Central::Signature) and at most SKEW seconds
      # old. Before a service sees it the Server checks who calls, once for
      # every service (#resolve): an account must be there and not banned —
      # its roles are the accounts', not what the board said —, a guest's
      # name must be no account's and look like none. Then the op runs, its
      # role checked, and one +central+ line goes to the log.
      #
      # The answers that are not a service's own: +unknown_op+,
      # +bad_request+ (missing fields), +forbidden+ (the op's role),
      # +unknown_account+, +banned+, +invalid_name+, +name_taken+ and +error+
      # (the service raised; logged); a request that is not signed, stale or
      # not JSON gets <tt>{ "error": … }</tt> and status 403 or 400.
      #
      # <tt>/health</tt> answers +ok+, or the problems of the services'
      # databases with status 503.
      class Server
        # Seconds a request's +ts+ may be off.
        SKEW = 60
        # The largest request taken, in bytes.
        MAX_BODY = 16_384

        # The services by path, a Hash of String => Service.
        attr_reader :services

        # A Central for +services+ (Service subclasses) with +accounts+ (the
        # board's Rubbs::Common::Auth::Directory, or +nil+ when no service asks
        # who calls), serving on +port+ of +host+ (+nil+: no HTTP, for
        # #dispatch alone). The services' databases are opened in +data+, the
        # board's data folder.
        def initialize(services:, accounts: nil, port: nil, host: '0.0.0.0', data: 'data')
          @accounts  = accounts
          @databases = open_databases(services, data)
          context    = Service::Context.new(accounts: accounts, databases: @databases)
          @services  = services.to_h { |service| [service.path, service.new(context)] }
          @http      = listen(port, host) if port
        end

        # The port it listens on (the one the system chose for port 0).
        def port = @http&.config&.[](:Port)

        # Serves in a Rubbs::Common::Board::Background thread. Returns the Thread.
        def start = Rubbs.background('central') { @http.start }

        # Stops serving and closes the services' databases.
        def stop
          @http&.shutdown
          @databases.each_value(&:disconnect)
        end

        # The answer to +body+ (the request's JSON) for +path+, signed
        # +signature+ (or, on <tt>/auth</tt>, the old +legacy+ one): a Hash.
        def answer(path, body, signature, legacy: nil)
          return { 'error' => 'signature' } unless signed?(path, body, signature, legacy)

          request = JSON.parse(body)
          return { 'error' => 'request' } unless request.is_a?(Hash)
          return { 'error' => 'stale' } unless (Time.now.to_i - request['ts'].to_i).abs <= SKEW

          dispatch(path, request)
        rescue JSON::ParserError
          { 'error' => 'json' }
        end

        # Runs the +request+ (a parsed Hash, signature checked or not needed:
        # a board's call on the Central itself) on the service at +path+ and
        # returns its answer, a Hash with String keys and a +result+.
        def dispatch(path, request)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          service = @services[path] or return { 'result' => 'unknown_service' }
          result  = Auth.asked_by(request['aud']) { run(service, request) }
          note(path, request, result, started)
          result
        end

        # Who +wire+ (the +actor+ of a request) is: an Actor, or why not
        # (+:unknown_account+, +:banned+, +:invalid_name+, +:name_taken+).
        def resolve(wire)
          wire = {} unless wire.is_a?(Hash)
          return account_actor(wire) if wire['id']

          guest_actor(wire)
        end

        # The problems of the services' databases, an Array of Strings.
        def health
          @databases.filter_map do |name, db|
            db.test_connection && nil
          rescue StandardError => e
            "central database #{name}: #{e.class}: #{e.message}"
          end
        end

        private

        def run(service, request)
          op = service.class.ops[request['op'].to_s] or return Service.answer(:unknown_op)
          actor = permitted(op, request['actor'])
          return Service.answer(actor) if actor.is_a?(Symbol)

          service.call(op, actor, request.except(*RESERVED))
        rescue ArgumentError => e
          failed(e, request, :bad_request, :warn)
        rescue StandardError => e
          failed(e, request, :error, :error)
        end

        # The Actor +wire+ is for +op+, or why it may not ask.
        def permitted(op, wire)
          return Actor.nobody unless op.actor

          actor = resolve(wire)
          return actor if actor.is_a?(Symbol)

          op.role && !actor.role?(op.role) ? :forbidden : actor
        end

        def failed(error, request, result, level)
          Rubbs.log('central', error, level: level, op: request['op'].to_s)
          Service.answer(result)
        end

        def account_actor(wire)
          found = @accounts&.resolve(wire['id']) || :unknown_account
          return found if found.is_a?(Symbol)

          Actor.new(id: found.id, name: found.name, roles: found.roles, caller_key: wire['caller_key'], face: wire['face'])
        end

        def guest_actor(wire)
          name = guest_name(wire['guest'].to_s)
          return name if name.is_a?(Symbol)

          Actor.guest(name, caller_key: wire['caller_key'], face: wire['face'])
        end

        # The name a guest gave, cleaned (+nil+: none), or why it cannot be one.
        def guest_name(raw)
          return nil if raw.strip.empty?

          name = Auth::Names.clean(raw) or return :invalid_name
          @accounts && (@accounts.known?(name) || @accounts.look_alike?(name)) ? :name_taken : name
        end

        def note(path, request, result, started)
          ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
          who = request['actor'].is_a?(Hash) ? request['actor']['id'] || 'guest' : nil
          Rubbs.log(
            'central',
            "#{path} #{request['op']}",
            service: path.delete_prefix('/'),
            op:      request['op'].to_s,
            aud:     request['aud'].to_s,
            actor:   who,
            result:  result['result'],
            ms:      ms
          )
        end

        def signed?(path, body, signature, legacy)
          return true if Signature.valid?(path, body, signature)

          path == '/auth' && !legacy.to_s.empty? && Signature.legacy_valid?(body, legacy)
        end

        def open_databases(services, data)
          databases = services.filter_map(&:database).to_h do |name, migrations|
            FileUtils.mkdir_p(data)
            [name, Storage::Database.open(File.join(data, "#{name}.sqlite3"), migrations)]
          end
          Storage::Model.bind(databases)
          databases
        end

        def listen(port, host)
          server = WEBrick::HTTPServer.new(Port: port, BindAddress: host, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
          @services.each_key { |path| server.mount_proc(path) { |request, response| respond(path, request, response) } }
          server.mount_proc('/health') { |_, response| healthy(response) }
          server
        end

        def respond(path, request, response)
          response['Content-Type'] = 'application/json'
          if request.request_method != 'POST' || request.body.to_s.bytesize > MAX_BODY
            response.status = 400
            return response.body = '{"error":"request"}'
          end

          result = answer(path, request.body.to_s, request[Signature::HEADER], legacy: request[Signature::LEGACY_HEADER])
          response.status = result['error'] ? 403 : 200
          response.body = JSON.generate(result)
        end

        def healthy(response)
          problems = health
          response.status = problems.empty? ? 200 : 503
          response.body = problems.empty? ? 'ok' : problems.join("\n")
        end
      end
    end
  end
end
