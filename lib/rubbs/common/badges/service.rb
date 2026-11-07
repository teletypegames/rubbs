# frozen_string_literal: true

module Rubbs
  module Common
    module Badges
      # The badges as a service of the Central, on <tt>/badges</tt>: the
      # boards send the events of their signed-in callers, the Central counts
      # them (Engine) by the badges of Rubbs::Common::Badges.catalog. A
      # network declares it on its Central (<tt>central serve: …, services:
      # [Rubbs::Common::Badges::Service]</tt>, or a subclass that adds to it).
      # Ops:
      #
      # [record] +event+, +fields+, +call+, +via+, +board+ (default the
      #          asker): keeps the fact of an account (a guest gets +guest+)
      #          and answers +earned+, the badges it earned (Badge#to_h with
      #          +tier+ and its +color+) and +notices+, what the observers
      #          (Badges.observers) tell the caller; each earned badge is a
      #          log line (+badges+ +earned+: badge, tier, board, account)
      # [mine]   the account's +badges+: Engine#progress
      # [hall]   (anyone) the +badges+ earned, how often, who first: Engine#hall
      # [grant]  (sysop) +account_id+, +name+, +badge+, +tier+: gives a badge
      class Service < Central::Service
        path     '/badges'
        database :badges, MIGRATIONS

        # The Engine on the service's database.
        attr_reader :engine

        # The service with the Central's +context+ and the badges of
        # +catalog+ (Rubbs::Common::Badges.catalog by default).
        def initialize(context, catalog: Badges.catalog)
          super(context)
          @catalog = catalog
          @engine  = Engine.new(database, catalog)
          Badges.recorder = self
        end

        op(:record) do |actor, event:, fields: {}, call: nil, via: nil, board: nil, **|
          next :guest if actor.guest?

          fact = Fact.make(name: event, board: board || asker, fields: fields.to_h, call: call, face: actor.face, via: via)
          { earned: keep(actor, fact), notices: Badges.notices(actor, fact) }
        end

        op(:mine) do |actor, **|
          next :guest if actor.guest?

          { badges: engine.progress(actor.id) }
        end

        op(:hall, actor: false) { |_, **| { badges: engine.hall } }

        op(:grant, role: :sysop) do |_, account_id:, name:, badge:, tier: nil, **|
          found = @catalog[badge] or next :unknown_badge

          engine.grant(account_id.to_i, name, found, tier: tier, board: asker) ? :ok : :had_it
        end

        # Keeps +fact+ (a Fact) of +actor+ (an account's
        # Rubbs::Common::Central::Actor) and logs what it earned. Returns the
        # badges earned, as #record answers them (Service.earned).
        def keep(actor, fact)
          awards = engine.record(actor.id, actor.name, fact)
          awards.each { |a| Service.log_earned(a, fact.board, actor.name) }
          awards.map { |award| Service.earned(award) }
        end

        # Writes the log line of +award+ (an Engine::Award) earned on +board+
        # by the account +name+: +badges+ +earned+ with the badge, tier,
        # board and account. Returns +nil+.
        def self.log_earned(award, board, name)
          Rubbs.log('badges', 'earned', badge: award.badge.key, tier: award.tier.to_s, board: board, account: name)
        end

        # An Engine::Award as an answer: the badge, its +tier+ and the
        # tier's +color+.
        def self.earned(award)
          award.badge.to_h.merge('tier' => award.tier, 'color' => award.badge.tier_color(award.tier).to_s)
        end
      end
    end
  end
end
