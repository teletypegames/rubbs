# frozen_string_literal: true

require 'test_helper'

class TerminalTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @session.define_singleton_method(:settle) { |**| true }
  end

  def teardown = @session.fake_line.close

  def ask(keys, cols: 80)
    @session.instance_variable_set(:@term_cols, cols)
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { BBS::Terminal::Question.new(@session, 'My board').ask }
  end

  def test_return_takes_the_guess
    assert_equal :modern, ask("\r")
    assert_equal :petscii, ask("\r", cols: 40)
  end

  def test_a_digit_picks_and_return_takes_it
    assert_equal :petscii, ask("2\r")
    assert_includes @session.received, 'COMMODORE 64'
  end

  def test_backspace_takes_the_pick_back
    assert_equal :modern, ask("2\b\r")
  end
end
