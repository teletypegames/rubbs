# frozen_string_literal: true

require 'date'

module Rubbs
  module Common
    module Badges
      # What a badge asks, as one sentence read left to right: which events
      # count, what is measured of them, in what window, and how much is
      # enough.
      #
      #   on(:call).distinct(:board).reaches 5
      #   on(:read, kind: 'rfc').distinct(:ref).tiers bronze: 10, silver: 50, gold: 250
      #   on(:call).streak(:days).reaches 7
      #   on(:read, kind: 'jargon').count.within(:call).reaches 20
      #   on(:call, hour: 0...4).once
      #
      # A rule is data: Catalog#problems checks it, Engine counts it, and a
      # profile shows how far a caller is (#value against #goals).
      class Rule
        # How each measure is taken of facts (and the rule's field): one is
        # enough, how many, how many different values of a field, the sum of
        # a field, the longest run of days or weeks.
        MEASURE = {
          once:     ->(facts, _) { facts.empty? ? 0 : 1 },
          count:    ->(facts, _) { facts.size },
          distinct: ->(facts, field) { facts.map { |f| f.field(field) }.compact.map(&:to_s).uniq.size },
          sum:      ->(facts, field) { facts.sum { |f| f.field(field).to_f } },
          streak:   ->(facts, unit) { Rule.longest_run(facts.map { |f| f.field('date') }.compact, unit) }
        }.freeze
        # The measures, by name.
        MEASURES = MEASURE.keys.freeze
        # The windows a measure can be taken in: one call, one day, one week.
        WINDOWS = %i[call day week].freeze
        # The units of a streak.
        STREAKS = %i[days weeks].freeze
        # The goal that grows with the network: every board of
        # Catalog#boards.
        ALL_BOARDS = :all_boards

        # The event's name (a String), the +filter+ (field => wanted value,
        # String keys), the +measure+ (one of MEASURES), the +field+ it
        # measures (or the unit of a streak), the +window+ (one of WINDOWS, or
        # +nil+) and the +goal+ (a number or ALL_BOARDS, +nil+ with tiers).
        attr_reader :event, :filter, :measure, :field, :window, :goal

        # A rule on the events named +event+ whose fields match +filter+:
        # a value (equal; a Symbol and a String are alike), an Array (any of
        # them), a Range (covers it) or a Regexp (matches it).
        def initialize(event, filter = {})
          @event   = event.to_s
          @filter  = filter.to_h { |k, v| [k.to_s, v] }.freeze
          @measure = :count
          @field   = nil
          @window  = nil
          @goal    = nil
          @tiers   = {}
        end

        # One such event is enough. Returns +self+.
        def once
          @measure = :once
          @goal = 1
          self
        end

        # Measures how many there are. Returns +self+.
        def count = measured(:count)

        # Measures how many different values of +field+ they have. Returns
        # +self+.
        def distinct(field) = measured(:distinct, field.to_s)

        # Measures the sum of the number in +field+. Returns +self+.
        def sum(field) = measured(:sum, field.to_s)

        # Measures the longest run of days (or weeks, +unit+ +:weeks+) with
        # such an event. Raises ArgumentError for another unit.
        def streak(unit = :days)
          raise ArgumentError, "a streak is in #{STREAKS.join(' or ')}" unless STREAKS.include?(unit)

          measured(:streak, unit.to_s)
        end

        # Takes the measure in each +window+ (+:call+, +:day+, +:week+) apart;
        # the best one counts. Returns +self+. Raises ArgumentError for another
        # window.
        def within(window)
          raise ArgumentError, "a window is one of #{WINDOWS.join(', ')}" unless WINDOWS.include?(window)

          @window = window
          self
        end

        # The goal: a number, or ALL_BOARDS. Returns +self+.
        def reaches(goal)
          @goal = goal
          self
        end

        # Sets the goals of the tiers, in order (<tt>bronze: 10, silver: 50,
        # gold: 250</tt>), each earned apart, and returns +self+; without
        # +tiers+ returns them (name => goal, empty without).
        def tiers(**tiers)
          return @tiers if tiers.empty?

          @tiers = tiers.transform_keys(&:to_s).freeze
          @goal = nil
          self
        end

        # The fields the filter names, Strings.
        def fields = @filter.keys

        # Whether +fact+ (a Fact) is one this rule counts.
        def match?(fact) = fact.name == @event && @filter.all? { |key, wanted| Rule.match_value?(wanted, fact.field(key)) }

        # The rule as a pattern of facts (#match?): <tt>facts.grep(rule)</tt>.
        alias === match?

        # Whether +actual+ (a field's value; an Array: any of its values) is
        # what +wanted+ asks (see #new).
        def self.match_value?(wanted, actual)
          return actual.any? { |a| match_value?(wanted, a) } if actual.is_a?(Array)
          return wanted.any? { |w| match_value?(w, actual) } if wanted.is_a?(Array)
          return covers?(wanted, actual) if wanted.is_a?(Range)
          return wanted.match?(actual.to_s) if wanted.is_a?(Regexp)

          wanted.to_s == actual.to_s
        end

        # Whether +range+ covers +actual+ (a number written as a String is
        # taken as the number when the range is of numbers).
        def self.covers?(range, actual)
          return false if actual.nil?

          actual = actual.to_f if actual.is_a?(String) && range.begin.is_a?(Numeric)
          range.cover?(actual)
        end

        # The longest run of consecutive days (+unit+ <tt>"days"</tt>) or
        # weeks in +dates+ (YYYY-MM-DD Strings): an Integer.
        def self.longest_run(dates, unit)
          step = unit == 'weeks' ? 7 : 1
          days = dates.map { |d| Rule.period(Date.parse(d), step) }.uniq.sort
          days.slice_when { |a, b| (b - a).to_i != step }.map(&:size).max || 0
        end

        # The first day of the period of +step+ days (1 or 7: the ISO week's
        # Monday) +date+ is in.
        def self.period(date, step) = step == 7 ? date - (date.cwday - 1) : date

        # The measure of +facts+ (the Facts that #match?), the best window's
        # when the rule has one: an Integer, or a Float for a sum.
        def value(facts)
          return measure_of(facts) unless @window

          facts.group_by { |f| window_key(f) }.values.map { |group| measure_of(group) }.max || 0
        end

        # The goals as [tier, number] pairs, lowest first: the tiers' names, or
        # one pair with a +nil+ tier. ALL_BOARDS is +boards+ (a number).
        def goals(boards)
          pairs = @tiers.empty? ? [[nil, @goal || 1]] : @tiers.to_a
          pairs.map { |tier, goal| [tier, goal == ALL_BOARDS ? boards : goal] }
        end

        private

        def measured(measure, field = nil)
          @measure = measure
          @field = field
          self
        end

        def window_key(fact)
          case @window
          when :call then fact.call
          when :day then fact.field('date')
          else fact.field('week')
          end
        end

        def measure_of(facts) = MEASURE.fetch(@measure).call(facts, @field)
      end
    end
  end
end
