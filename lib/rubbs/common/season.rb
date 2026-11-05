# frozen_string_literal: true

require 'date'

module Rubbs
  module Common
    # The time of day, the season and the holidays at a place, for choosing
    # the layers of a Rubbs::Common::Art: the sky of a scene at dawn, by day, at dusk or
    # at night, snow in winter, a pumpkin at the end of October, fireworks on
    # New Year's Eve, bunting in the week of a game jam.
    #
    # Pure and deterministic: everything follows from the instant (+at+,
    # default now), the time zone and the place, so a test passes the time it
    # wants.
    #
    #   s = Rubbs::Common::Season.now                         # Budapest, now
    #   s.time_of_day                               # => :night
    #   s.layers                                    # => [:snow]
    #   art.with(*s.layers)
    #
    #   Rubbs::Common::Season.now(at: Time.utc(2026, 12, 31, 21), jam: Date.new(2027, 1, 8)..Date.new(2027, 1, 10))
    #   # => fireworks and snow, at night
    #
    # The times of day follow the sun: +:dawn+ is the hour around sunrise
    # (TWILIGHT minutes either side), +:day+ until the hour around sunset,
    # +:dusk+, and +:night+ after it. Sunrise and sunset are worked out for
    # +latitude+ and +longitude+ (Budapest by default) to within a few
    # minutes.
    #
    # The layers, a Symbol each:
    #
    # [+:snow+]      December to February
    # [+:pumpkin+]   PUMPKIN: the last week of October
    # [+:fireworks+] New Year's Eve, and the small hours of New Year's Day
    #                (until FIREWORKS_UNTIL)
    # [+:bunting+]   the days of +jam+, a Range of Date
    class Season
      # Budapest's latitude.
      LATITUDE  = 47.4979
      # Budapest's longitude.
      LONGITUDE = 19.0402
      # The minutes on either side of sunrise that are dawn, and of sunset
      # that are dusk.
      TWILIGHT = 45
      # The days of the pumpkin: the month and the days of the month.
      PUMPKIN = [10, 24..31].freeze
      # The hour of New Year's Day the fireworks stop.
      FIREWORKS_UNTIL = 6
      # The months of the snow.
      SNOW = [12, 1, 2].freeze
      # The seasons by month (meteorological: winter is December to February).
      SEASONS = {
        12 => :winter,
        1  => :winter,
        2  => :winter,
        3  => :spring,
        4  => :spring,
        5  => :spring,
        6  => :summer,
        7  => :summer,
        8  => :summer,
        9  => :autumn,
        10 => :autumn,
        11 => :autumn
      }.freeze
      # The time zones known without the +tzinfo+ gem: name => [standard
      # offset in seconds, whether it keeps EU summer time].
      ZONES = {
        'UTC'           => [0, false],
        'Etc/UTC'       => [0, false],
        'Europe/London' => [0, true],
        'Europe/Dublin' => [0, true],
        'Europe/Lisbon' => [0, true],
        **%w[Amsterdam Belgrade Berlin Bratislava Brussels Budapest Copenhagen Ljubljana Madrid Oslo Paris
             Prague Rome Stockholm Vienna Warsaw Zagreb Zurich].to_h { |c| ["Europe/#{c}", [3600, true]] },
        **%w[Athens Bucharest Helsinki Kyiv Riga Sofia Tallinn Vilnius].to_h { |c| ["Europe/#{c}", [7200, true]] }
      }.freeze
      # A fixed offset written as a time zone: +01:00, -0530.
      OFFSET_RE = /\A([+-])(\d\d):?(\d\d)\z/

      # The local time (a Time with the zone's offset).
      attr_reader :time
      # +:dawn+, +:day+, +:dusk+ or +:night+.
      attr_reader :time_of_day
      # +:winter+, +:spring+, +:summer+ or +:autumn+.
      attr_reader :season
      # The holiday and season layers in effect, an Array of Symbol (see the
      # class description).
      attr_reader :layers
      # Today's sunrise and sunset, local Times (+nil+ on a day the sun does
      # not rise or set).
      attr_reader :sunrise, :sunset

      # The Season at +at+ (a Time, default now) in time zone +tz+.
      #
      # [tz]        a zone name: one of ZONES, any IANA name when the +tzinfo+
      #             gem is installed, or a fixed offset (<tt>'+01:00'</tt>);
      #             or an object with +utc_offset_at+ / a TZInfo::Timezone
      # [jam]       the days of a game jam, a Range of Date (or of
      #             <tt>'YYYY-MM-DD'</tt> Strings), for +:bunting+; +nil+ for none
      # [latitude]  the place's latitude, for the sun
      # [longitude] the place's longitude, east positive
      #
      # Raises ArgumentError for a time zone it does not know.
      def self.now(tz: 'Europe/Budapest', at: Time.now, jam: nil, latitude: LATITUDE, longitude: LONGITUDE)
        new(at.getlocal(offset(tz, at.getutc)), jam: jam, latitude: latitude, longitude: longitude)
      end

      # The Season of +time+, a Time in the local zone already (see ::now for
      # the arguments).
      def initialize(time, jam: nil, latitude: LATITUDE, longitude: LONGITUDE)
        @time = time
        @latitude = latitude
        @season = SEASONS.fetch(time.month)
        @sunrise, @sunset = local_sun(latitude, longitude)
        @time_of_day = find_time_of_day
        @layers = find_layers(jam)
      end

      # Whether it is dawn.
      def dawn? = @time_of_day == :dawn

      # Whether it is day.
      def day? = @time_of_day == :day

      # Whether it is dusk.
      def dusk? = @time_of_day == :dusk

      # Whether it is night.
      def night? = @time_of_day == :night

      # Whether layer +name+ (a Symbol or String) is in effect.
      def layer?(name) = @layers.include?(name.to_sym)

      # Every name in effect: the time of day, the season and the layers, for
      # <tt>art.with(*season.names)</tt> when an art has layers by those
      # names.
      def names = [@time_of_day, @season, *@layers]

      private

      def local_sun(latitude, longitude)
        rise, set = Season.sun(@time.to_date, latitude, longitude)
        return [nil, nil] unless rise

        midnight = Time.new(@time.year, @time.month, @time.day, 0, 0, 0, @time.utc_offset)
        [(midnight + (rise * 60) + @time.utc_offset).round, (midnight + (set * 60) + @time.utc_offset).round]
      end

      def find_time_of_day
        # Polar day or night: the summer half of the year is day on the
        # sun's side of the equator.
        return ((4..9).cover?(@time.month) == @latitude.positive? ? :day : :night) unless @sunrise

        twilight = TWILIGHT * 60
        if @time < @sunrise - twilight || @time >= @sunset + twilight then :night
        elsif @time < @sunrise + twilight then :dawn
        elsif @time < @sunset - twilight then :day
        else :dusk
        end
      end

      def find_layers(jam)
        date = @time.to_date
        {
          snow:      SNOW.include?(date.month),
          pumpkin:   pumpkin?(date),
          fireworks: fireworks?(date),
          bunting:   jam_day?(jam, date)
        }.select { |_, on| on }.keys
      end

      def pumpkin?(date) = date.month == PUMPKIN[0] && PUMPKIN[1].cover?(date.day)

      def fireworks?(date)
        (date.month == 12 && date.day == 31) || (date.month == 1 && date.day == 1 && @time.hour < FIREWORKS_UNTIL)
      end

      def jam_day?(jam, date)
        return false unless jam

        date.between?(*[jam.first, jam.last].map { |d| d.is_a?(Date) ? d : Date.parse(d.to_s) })
      end
    end
  end
end

require_relative 'season/clock'
