# frozen_string_literal: true

require 'test_helper'

class TelnetTest < Minitest::Test
  T = Rubbs::Common::Line::Telnet

  def setup = @session = FakeSession.new
  def teardown = @session.fake_line.close

  def type(bytes) = @session.fake_line.caller.write(bytes.b)

  def test_naws_is_clamped
    @session.resize!(1000, 1000)
    assert_equal [255, 100], [@session.term_cols, @session.term_rows]
    @session.resize!(1, 1)
    assert_equal [20, 8], [@session.term_cols, @session.term_rows]
  end

  def test_a_naws_report_among_the_keys_resizes
    type("#{[T::IAC, T::SB, T::NAWS_OPT, 0, 100, 0, 40, T::IAC, T::SE].pack('C*')}k")
    assert_equal 'k', @session.readkey
    assert_equal [100, 40], [@session.term_cols, @session.term_rows]
    assert @session.naws_reported?
  end

  def test_keys
    type("a\r\n\t\x7f\x03\x01\e[A\eOP\e[15;5~\e[Z\ex")
    keys = Array.new(11) { @session.readkey }
    assert_equal ['a', :enter, :tab, :backspace, :interrupt, :ctrl_a, :up, :f1, :ctrl_f5, :shift_tab, :alt_x], keys
  end

  def test_utf8_and_a_lone_escape
    type("é\e")
    assert_equal 'é', @session.readkey
    assert_equal :escape, @session.readkey
  end

  def test_sgr_mouse
    type("\e[<0;10;5M\e[<64;1;1M")
    press = @session.readkey
    assert_equal [:press, :left, 10, 5], [press.kind, press.button, press.x, press.y]
    wheel = @session.readkey
    assert_equal %i[wheel up], [wheel.kind, wheel.button]
  end

  def test_idle
    assert_equal :idle, @session.readkey(timeout: 0.05)
  end

  def test_readline_edits_and_masks
    type("ab\x7fc\r")
    assert_equal 'ac', @session.readline(mask: '*')
    assert_equal "**\b \b*\r\n", @session.received
  end

  def test_read_raw_byte_keeps_a_doubled_iac
    type("\xFF\xFF\xFF\xFB\x01A")
    assert_equal [255, 65], [@session.read_raw_byte(1), @session.read_raw_byte(1)]
  end

  def test_settle_waits_for_the_window_size
    type([T::IAC, T::SB, T::NAWS_OPT, 0, 90, 0, 30, T::IAC, T::SE].pack('C*'))
    assert @session.settle(timeout: 1)
    refute FakeSession.new.settle(timeout: 0.05)
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
