# frozen_string_literal: true

require 'json'

module Rubbs
  module Common
    module Badges
      # The counting of the Central's Service: the facts of an account in
      # its +badge_events+ table and the badges it earned in +badge_awards+
      # (MIGRATIONS). #record keeps a fact and gives what it earned; #progress
      # tells how far an account is with every badge.
      class Engine
        # A badge earned now: the Badge and its +tier+ (+nil+ without tiers).
        Award = Data.define(:badge, :tier)

        # An engine on +db+ (a Sequel::Database migrated by MIGRATIONS) for
        # the badges of +catalog+ (a Catalog).
        def initialize(db, catalog)
          @db      = db
          @catalog = catalog
        end

        # Keeps +fact+ (a Fact) of +account+ (its id) named +name+ and gives
        # what it earned: the Awards of the badges whose rule counts it, then
        # of the composites they complete.
        def record(account, name, fact)
          @db[:badge_events].insert(
            account_id: account,
            board:      fact.board,
            name:       fact.name,
            fields:     JSON.generate(fact.fields),
            at:         fact.at,
            call:       fact.call
          )
          earned = @catalog.counting(fact).flat_map { |badge| award(account, name, badge, fact.board) }
          earned + composites(account, name, fact.board)
        end

        # Gives +badge+ (a Badge, at +tier+) to +account+ named +name+ on
        # +board+, unless it has it already. Returns the award's row (a Hash)
        # when it was given, +nil+ when the account had it.
        def grant(account, name, badge, tier: nil, board: nil, at: Time.now.to_i)
          key = { account_id: account, badge: badge.key, tier: tier.to_s }
          return nil if @db[:badge_awards].where(key).any?

          row = key.merge(name: name.to_s, board: board.to_s, awarded_at: at)
          @db[:badge_awards].insert(row)
          row
        end

        # The tiers of each badge +account+ has, badge key => [tier, ...] (a
        # tier is "" without tiers).
        def awards(account)
          @db[:badge_awards].where(account_id: account).select_map(%i[badge tier])
            .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
        end

        # How far +account+ is with each badge: Hashes of the badge
        # (Badge#to_h), its +value+, +goals+ ([tier, number] pairs) and the
        # tiers +earned+.
        def progress(account)
          earned = awards(account)
          facts  = Hash.new { |h, event| h[event] = facts_of(account, event) }
          @catalog.badges.values.map do |badge|
            value = value_of(badge, facts, earned)
            badge.to_h.merge('value' => value, 'goals' => badge.goals(boards), 'earned' => earned.fetch(badge.key, []))
          end
        end

        # The badges in numbers, for a board's metrics: +awards+ ([badge,
        # tier] => accounts), +accounts+ (accounts with any badge), +events+
        # ([name, board] => facts kept) and +defined+ (board => badges).
        def statistics
          {
            awards:   counts(:badge_awards, :badge, :tier),
            accounts: @db[:badge_awards].select(:account_id).distinct.count,
            events:   counts(:badge_events, :name, :board),
            defined:  @catalog.badges.values.group_by(&:board).transform_values(&:size)
          }
        end

        # How many accounts have each badge, and who was first: Hashes of
        # the badge, +count+, +first+ (a name) and +first_at+.
        def hall
          rows = @db[:badge_awards].order(:awarded_at).all
          rows.group_by { |r| r[:badge] }.filter_map do |key, awards|
            badge = @catalog[key] or next
            badge.to_h.merge(
              'count'    => awards.map { |a| a[:account_id] }.uniq.size,
              'first'    => awards.first[:name],
              'first_at' => awards.first[:awarded_at]
            )
          end
        end

        private

        def counts(table, first, second)
          @db[table].group_and_count(first, second).to_h { |r| [[r[first], r[second]], r[:count]] }
        end

        def boards = @catalog.boards.size

        def facts_of(account, event)
          @db[:badge_events].where(account_id: account, name: event).order(:at).map do |row|
            Fact.new(name: row[:name], board: row[:board], fields: JSON.parse(row[:fields]), at: row[:at], call: row[:call])
          end
        end

        def value_of(badge, facts, earned)
          return badge.parts.count { |p| earned.key?(p) } if badge.composite?
          return earned.key?(badge.key) ? 1 : 0 unless badge.rule

          badge.rule.value(facts[badge.rule.event].grep(badge.rule))
        end

        def award(account, name, badge, board)
          value = badge.rule.value(facts_of(account, badge.rule.event).grep(badge.rule))
          badge.goals(boards).filter_map do |tier, goal|
            Award.new(badge, tier) if goal.positive? && value >= goal && grant(account, name, badge, tier: tier, board: board)
          end
        end

        def composites(account, name, board)
          earned = awards(account)
          @catalog.composites.filter_map do |badge|
            next if earned.key?(badge.key) || badge.parts.count { |p| earned.key?(p) } < badge.needed

            Award.new(badge, nil) if grant(account, name, badge, board: board)
          end
        end
      end

      # The tables of the badges on the Central: the facts of each account
      # and the badges it earned (a tier is "" without tiers).
      MIGRATIONS = [
        <<~SQL
          CREATE TABLE badge_events (
            id         INTEGER PRIMARY KEY,
            account_id INTEGER NOT NULL,
            board      TEXT NOT NULL,
            name       TEXT NOT NULL,
            fields     TEXT NOT NULL,
            at         INTEGER NOT NULL,
            call       TEXT
          );
          CREATE INDEX badge_events_account ON badge_events (account_id, name);
          CREATE TABLE badge_awards (
            account_id INTEGER NOT NULL,
            badge      TEXT NOT NULL,
            tier       TEXT NOT NULL DEFAULT '',
            name       TEXT NOT NULL,
            board      TEXT,
            awarded_at INTEGER NOT NULL,
            PRIMARY KEY (account_id, badge, tier)
          );
          CREATE INDEX badge_awards_badge ON badge_awards (badge, awarded_at);
        SQL
      ].freeze
    end
  end
end
