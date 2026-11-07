# frozen_string_literal: true

module Rubbs
  module Common
    module Badges
      # One event of an account, as the Central keeps it: its +name+, the
      # +board+ it happened on, its +fields+ (String keys: the board's own and
      # the ones of DERIVED), when (+at+, epoch seconds) and the +call+ it
      # came in (a session id, or +nil+).
      Fact = Data.define(:name, :board, :fields, :at, :call) do
        # The value of the field +key+: +board+ and +call+ are the fact's own,
        # the rest are in #fields.
        def field(key)
          case key.to_s
          when 'board' then board
          when 'call' then call
          else fields[key.to_s]
          end
        end

        # A fact named +name+ on +board+ with the board's +fields+, +at+ (a
        # Time), the +face+ and +via+ of the call, and the fields of DERIVED
        # worked out in time zone +tz+ (Rubbs::Common::Season).
        def self.make(name:, board:, fields: {}, at: Time.now, call: nil, face: nil, via: nil, tz: Badges.time_zone)
          own = fields.to_h { |k, v| [k.to_s, v] }.reject { |k, _| DERIVED.include?(k) || %w[board call].include?(k) }
          derived = { 'face' => face&.to_s, 'via' => via&.to_s }.compact.merge(timing(at, tz))
          new(name: name.to_s, board: board.to_s, fields: own.merge(derived), at: at.to_i, call: call&.to_s)
        end

        # The fields of the time +at+ in zone +tz+: hour, weekday, date, ISO
        # week, time of day, and the season with its layers.
        def self.timing(at, tz)
          season = Season.now(tz: tz, at: at)
          local  = season.time
          {
            'hour'        => local.hour,
            'weekday'     => local.strftime('%A').downcase,
            'date'        => local.strftime('%F'),
            'week'        => local.strftime('%G-W%V'),
            'time_of_day' => season.time_of_day.to_s,
            'season'      => [season.season, *season.layers].map(&:to_s)
          }
        end
      end

      # The fields every Fact gets from the Central, beside +board+ and
      # +call+: the face and the way of the call, and the time of it in the
      # network's zone (hour, weekday, date, ISO week, time of day, and the
      # season with its layers: +snow+, +pumpkin+, +fireworks+, +bunting+).
      DERIVED = %w[face via hour weekday date week time_of_day season].freeze
    end
  end
end
