# frozen_string_literal: true

module Rubbs
  module Common
    module Badges
      # Every badge a process knows, from every Set it loaded (Rubbs.badges),
      # with the events each board said it reports. The Central loads every
      # board's; a board loads its own and the network's, to send only the
      # events some badge counts (#counts?).
      class Catalog
        # The events every board reports by itself, with their fields:
        # +call+ (a signed-in caller reached the board), +use+ (a section
        # opened, Rubbs::Common::Log.use), +hangup+ (the call ended).
        BUILT_IN = { 'call' => [], 'use' => %w[name kind], 'hangup' => %w[minutes] }.freeze

        # The badges by key, in the order they were declared.
        attr_reader :badges

        # The events by name, each with the fields declared for it.
        attr_reader :events

        # An empty catalog.
        def initialize
          @badges = {}
          @events = BUILT_IN.transform_values(&:dup)
          @boards = nil
        end

        # The boards of the network (technical names): what Rule::ALL_BOARDS
        # counts. Set it with an Array or a block that answers one.
        def boards = Array(@boards.respond_to?(:call) ? @boards.call : @boards)

        # Sets the boards of the network (see #boards).
        attr_writer :boards

        # Adds the badges of +set+ (a Set) and its events. Raises
        # ArgumentError for a key already taken.
        def add(set)
          set.events.each { |name, fields| (@events[name] ||= []).concat(fields).uniq! }
          set.badges.each do |badge|
            raise ArgumentError, "the badge #{badge.key} is declared twice" if @badges.key?(badge.key)

            @badges[badge.key] = badge
          end
          self
        end

        # The Badge of +key+, or +nil+.
        def [](key) = @badges[key.to_s]

        # The badges whose rule counts +fact+ (a Fact).
        def counting(fact) = @badges.values.select { |b| b.rule&.match?(fact) }

        # The composite badges (Badge#composite?).
        def composites = @badges.values.select(&:composite?)

        # Whether any badge counts an event +name+ on +board+ with +fields+:
        # what a board asks before it sends one. The fields of
        # Rubbs::Common::Badges::DERIVED are not known yet, so a filter on one
        # of them is taken as met.
        def counts?(name, board, fields = {})
          probe = Fact.new(name: name.to_s, board: board.to_s, fields: fields.to_h { |k, v| [k.to_s, v] }, at: 0, call: nil)
          @badges.each_value.any? { |b| b.rule && b.rule.event == probe.name && known_fields_match?(b.rule, probe) }
        end

        # What is wrong with the badges, Strings (empty when nothing is): an
        # event no board declares, a filter on a field the event does not
        # have, tiers out of order, a part that is no badge, no title, hint or
        # emblem.
        def problems = @badges.values.flat_map { |b| problems_of(b).map { |p| "badge #{b.key}: #{p}" } }

        private

        def known_fields_match?(rule, probe)
          rule.filter.all? do |key, wanted|
            next true if DERIVED.include?(key)

            Rule.match_value?(wanted, probe.field(key))
          end
        end

        def problems_of(badge)
          [*look_problems(badge), *badge.parts.reject { |p| @badges.key?(p) }.map { |p| "#{p} is no badge" },
           *('no rule' unless badge.rule || badge.composite? || badge.manual?),
           *(badge.rule ? rule_problems(badge.rule) : [])]
        end

        def look_problems(badge)
          [('no hint' if badge.hint.empty?), ('no emblem' if badge.emblem.to_s.empty?),
           ("the colour #{badge.color} is not one of Badge::COLORS" unless Badge::COLORS.include?(badge.color))].compact
        end

        def rule_problems(rule)
          fields = @events[rule.event]
          return ["no board reports the event #{rule.event}"] unless fields

          known = fields + DERIVED + %w[board call]
          problems = rule.fields.reject { |f| known.include?(f) }.map { |f| "the event #{rule.event} has no field #{f}" }
          problems << 'the tiers are not in order' unless in_order?(rule.goals(1).map(&:last))
          problems
        end

        def in_order?(goals) = goals.all?(Numeric) && goals.each_cons(2).all? { |a, b| a < b }
      end
    end
  end
end
