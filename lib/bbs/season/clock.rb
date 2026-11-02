# frozen_string_literal: true

module BBS
  class Season
    # The class methods of a Season for the clock and the sky: the offset of
    # a time zone (Season.offset), EU summer time (Season.eu_summer?) and
    # the sunrise and sunset of a day (Season.sun).
    module Clock
      # The sun's declination in radians as a NOAA series over the
      # fractional year: the constant and the [cos, sin] of each harmonic.
      DECLINATION = [0.006918, [[-0.399912, 0.070257], [-0.006758, 0.000907], [-0.002697, 0.00148]]].freeze
      # The equation of time (over 229.18 minutes) as a NOAA series.
      EQUATION_OF_TIME = [0.000075, [[0.001868, -0.032077], [-0.014615, -0.040849]]].freeze

      # The offset from UTC in seconds of time zone +tz+ (see Season.now) at
      # +utc+, a Time. Raises ArgumentError for a zone it does not know.
      def offset(tz, utc)
        return tz.utc_offset_at(utc) if tz.respond_to?(:utc_offset_at)
        return tz.period_for_utc(utc).utc_total_offset if tz.respond_to?(:period_for_utc)

        name = tz.to_s
        return fixed_offset(name) if OFFSET_RE.match?(name)
        return zone_offset(name, utc) if ZONES.key?(name)

        tzinfo(name).period_for_utc(utc).utc_total_offset
      end

      # Whether EU summer time is in force at +utc+: from 01:00 UTC on the
      # last Sunday of March to 01:00 UTC on the last Sunday of October.
      def eu_summer?(utc)
        year = utc.year
        utc >= Time.utc(year, 3, last_sunday(year, 3), 1) && utc < Time.utc(year, 10, last_sunday(year, 10), 1)
      end

      # The day of the month of the last Sunday of +month+ in +year+.
      def last_sunday(year, month)
        last = Date.new(year, month, -1)
        last.day - last.wday
      end

      # Sunrise and sunset on +date+ (a Date) at +latitude+, +longitude+, in
      # minutes after midnight UTC (Floats): <tt>[rise, set]</tt>, or
      # <tt>[nil, nil]</tt> for polar day or night. The NOAA approximation.
      def sun(date, latitude, longitude)
        g  = 2 * Math::PI / 365 * (date.yday - 1)
        ha = hour_angle(latitude * Math::PI / 180, series(DECLINATION, g))
        return [nil, nil] unless ha

        [ha, -ha].map { |h| 720 - (4 * (longitude + h)) - (229.18 * series(EQUATION_OF_TIME, g)) }
      end

      private

      # The value of a NOAA Fourier series, <tt>[constant, [[cos, sin],
      # …]]</tt>, at the fractional year +g+.
      def series((constant, terms), g)
        constant + terms.each_with_index.sum { |(c, s), i| (c * Math.cos((i + 1) * g)) + (s * Math.sin((i + 1) * g)) }
      end

      # The sun's hour angle at sunrise in degrees at latitude +lat+ and
      # declination +decl+ (radians); +nil+ when it does not rise or set.
      def hour_angle(lat, decl)
        cos_ha = (Math.cos(90.833 * Math::PI / 180) / (Math.cos(lat) * Math.cos(decl))) - (Math.tan(lat) * Math.tan(decl))
        Math.acos(cos_ha) * 180 / Math::PI if cos_ha.between?(-1, 1)
      end

      def fixed_offset(name)
        sign, hours, minutes = OFFSET_RE.match(name).captures
        (sign == '-' ? -1 : 1) * ((hours.to_i * 3600) + (minutes.to_i * 60))
      end

      def zone_offset(name, utc)
        standard, summer = ZONES[name]
        standard + (summer && eu_summer?(utc) ? 3600 : 0)
      end

      # The TZInfo::Timezone named +name+. Raises ArgumentError when the
      # +tzinfo+ gem is missing or does not know the name.
      def tzinfo(name)
        require 'tzinfo'
        TZInfo::Timezone.get(name)
      rescue LoadError
        raise ArgumentError, "time zone #{name} needs the tzinfo gem (known without it: #{ZONES.keys.join(', ')})"
      rescue StandardError => e
        raise ArgumentError, "unknown time zone #{name}: #{e.message}"
      end
    end

    extend Clock
  end
end
