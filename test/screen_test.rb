# frozen_string_literal: true

require 'test_helper'

class ScreenTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @screen  = BBS::Petscii::Screen.new(@session, cols: 40, rows: 25)
  end

  def teardown = @session.fake_line.close

  def keys(input) = @session.fake_line.caller.write(input)

  def test_say_wraps_in_the_colour_given
    @screen.say('hello there', color: BBS::Petscii::Colors::RD)
    assert_includes @session.received, " #{BBS::Petscii::Colors::RD}hello there"
  end

  def test_pause_waits_for_a_key
    keys("\r")
    assert_equal :enter, Timeout.timeout(5) { @screen.pause }
    assert_includes @session.received, 'return: back'
  end

  def test_choose_takes_one_of_the_keys
    keys('xY')
    assert_equal 'y', Timeout.timeout(5) { @screen.choose('sure? ', %w[y n]) }
  end

  def test_pick_lists_the_items_and_returns_the_one_taken
    keys("2\r")
    assert_equal 'b', Timeout.timeout(5) { @screen.pick('letters', %w[a b c]) }
  end

  def test_pick_of_nothing_says_so
    keys("\r")
    assert_nil Timeout.timeout(5) { @screen.pick('letters', []) }
    assert_includes @session.received, BBS::Petscii::Screen::EMPTY
  end

  def test_actions_take_a_key_on_one_row
    keys('d')
    assert_equal 'd', Timeout.timeout(5) { @screen.actions(%w[d download], %w[q back]) }
  end

  def test_page_turns_until_the_last
    keys("\r\r")
    assert_nil Timeout.timeout(5) { @screen.page('long', Array.new(30) { |i| "line #{i}" }) }
    assert_includes @session.received, 'line 29'
  end
end
