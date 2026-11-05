# frozen_string_literal: true

require 'test_helper'

class SeasonTest < Minitest::Test
  def season(utc, **) = Rubbs::Common::Season.now(at: utc, **)

  def test_budapest_noon_in_july_is_a_summer_day
    s = season(Time.utc(2026, 7, 1, 10))
    assert_equal %i[summer day], [s.season, s.time_of_day]
    assert_equal 7200, s.time.utc_offset
    assert s.sunrise < s.time && s.time < s.sunset
  end

  def test_layers_of_the_holidays
    assert season(Time.utc(2026, 10, 28, 12)).layer?(:pumpkin)
    assert season(Time.utc(2026, 12, 31, 20)).layer?(:fireworks)
    assert season(Time.utc(2027, 1, 15, 12)).layer?(:snow)
    assert season(Time.utc(2026, 5, 2, 12), jam: '2026-05-01'..'2026-05-03').layer?(:bunting)
  end

  def test_offsets_and_summer_time
    assert_equal 19_800, Rubbs::Common::Season.offset('+05:30', Time.utc(2026, 1, 1))
    assert_equal 3600, Rubbs::Common::Season.offset('Europe/London', Time.utc(2026, 7, 1))
    assert_equal 0, Rubbs::Common::Season.offset('Europe/London', Time.utc(2026, 12, 1))
  end

  def test_polar_day
    assert_equal :day, season(Time.utc(2026, 6, 21, 0), latitude: 80).time_of_day
  end
end
