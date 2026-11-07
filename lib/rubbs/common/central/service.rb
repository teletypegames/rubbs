# frozen_string_literal: true

module Rubbs
  module Common
    module Central
      # A service of the Central: its path, its database and its ops. A
      # network declares one by subclassing; the Central's
      # Rubbs::Common::Central::Server makes one of each with its Context and
      # calls the ops, the other boards reach them through a
      # Rubbs::Common::Central::Proxy.
      #
      #   class Feedback < Rubbs::Common::Central::Service
      #     path     '/feedback'
      #     database :feedback, MIGRATIONS          # data/feedback.sqlite3 on the Central
      #
      #     op(:send) { |actor, subject:, body:, **| store.add(actor, subject, body) }
      #     op(:list, role: :sysop) { |_actor, state: nil, **| { items: store.list(state) } }
      #   end
      #
      # An op's block runs in the service with the checked Actor and the
      # request's other fields as keywords (take the rest with <tt>**</tt>).
      # It answers
      #
      # - a Symbol: <tt>{ "result": "<symbol>" }</tt> (+:ok+, +:limited+ …);
      # - a Hash: the answer as it is when it has a +result+, else with
      #   <tt>result: "ok"</tt> added;
      # - anything else JSON can carry: <tt>{ "result": "ok", "value": … }</tt>.
      #
      # [role]  the op is only for actors with this role (+forbidden+ else)
      # [actor] +false+ when the op does not ask who calls (the actor is not
      #         checked; it gets Actor.nobody)
      class Service
        # An op: its +name+ (a String), the +role+ it needs or +nil+, whether
        # it checks the +actor+, and its +block+.
        Op = Data.define(:name, :role, :actor, :block)

        # What the Central lends its services: the board's +accounts+ (a
        # Rubbs::Common::Auth::Directory, or +nil+) and the +databases+ the
        # services declared, by name (Sequel::Database each).
        Context = Data.define(:accounts, :databases)

        class << self
          # Sets the service's path (<tt>'/wall'</tt>) or, without +value+,
          # returns it: the one set, else a parent service's, else <tt>/</tt>
          # and the last part of the class name in lower case.
          def path(value = nil)
            return @path = value.to_s if value
            return @path if @path
            return superclass.path if inherits?

            "/#{name.to_s.split('::').last.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase}"
          end

          # The service's key: its path without the slash, a Symbol.
          def key = path.delete_prefix('/').to_sym

          # Declares the database +name+ of the service, migrated by
          # +migrations+ (Rubbs::Common::Storage::Database.migrate). The Central keeps it
          # in its data folder as <tt><name>.sqlite3</tt> and binds the
          # Rubbs::Common::Storage::Model classes whose table lives in it.
          def database(name = nil, migrations = [])
            return @database || (superclass.database if inherits?) unless name

            @database = [name.to_sym, migrations]
          end

          # Declares the op +name+ (see the class comment).
          def op(name, role: nil, actor: true, &block)
            raise ArgumentError, "the op #{name} needs a block" unless block

            ops[name.to_s] = Op.new(name: name.to_s, role: role&.to_s, actor: actor, block: block)
          end

          # The ops by name, a Hash of String => Op: a parent service's too, so
          # a subclass adds to them (or replaces one of the same name).
          def ops = @ops ||= inherits? ? superclass.ops.dup : {}

          # Whether the service is a subclass of another service (not of
          # Service itself): its path, database and ops are the parent's
          # unless it says otherwise.
          def inherits? = (superclass < Service) == true

          # The answer of an op's +value+ as it goes on the line: a Hash with
          # String keys and a +result+.
          def answer(value)
            body = case value
                   when Symbol then { 'result' => value.to_s }
                   when Hash then value.key?(:result) || value.key?('result') ? value : { result: 'ok', **value }
                   else { result: 'ok', value: value }
                   end
            JSON.parse(JSON.generate(body))
          end
        end

        # The Context the Central made the service with.
        attr_reader :context

        # A service with the Central's +context+ (a Context). A subclass that
        # keeps more (a store) makes it here and calls +super+.
        def initialize(context)
          @context = context
        end

        # Runs +op+ (an Op of this class) for +actor+ with +params+ (a Hash of
        # the request's other fields) and returns its answer (see ::answer).
        def call(op, actor, params)
          self.class.answer(instance_exec(actor, **params.transform_keys(&:to_sym), &op.block))
        end

        # The board that asked, its technical name (+aud+ of the request).
        def asker = Thread.current[Auth::ASKER].to_s

        # The database +name+ of the Context (+nil+ when there is none).
        def database(name = self.class.database&.first) = context.databases[name]
      end
    end
  end
end
