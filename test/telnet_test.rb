# frozen_string_literal: true

require 'test_helper'

class TelnetTest < Minitest::Test
  def setup = @session = FakeSession.new
  def teardown = @session.fake_line.close

  def test_naws_is_clamped
    @session.resize!(1000, 1000)
    assert_equal [255, 100], [@session.term_cols, @session.term_rows]
    @session.resize!(1, 1)
    assert_equal [20, 8], [@session.term_cols, @session.term_rows]
  end

  def test_a_write_timeout_ends_the_line
    @session.fake_line.board.timeout = 0.2
    assert_raises(IOError) { 100.times { @session.write('x' * 65_536) } }
    assert @session.line.closed?
  end

  def test_other_write_errors_are_swallowed
    @session.fake_line.caller.close
    assert_nil @session.write('x' * 1_000_000)
  end
end
