# frozen_string_literal: true

require 'test_helper'

class FrameBufferTest < Minitest::Test
  def setup
    @buffer = BBS::FrameBuffer.new(20, 2)
    @blank  = BBS::FrameBuffer.new(20, 2)
  end

  def row(buffer = @buffer) = (0...20).map { |c| buffer.send(:cell_at, 0, c).char }.join.rstrip

  def test_write_drops_controls
    @buffer.move(1, 1)
    @buffer.write("a\eb\u0085c\u202Ed\u0000e\u007Ff\ng")
    assert_equal 'abcdefg', row
  end

  def test_write_scrubs_invalid_bytes
    @buffer.move(1, 1)
    @buffer.write("x\xFFy".b)
    assert_equal 'x?y', row
  end

  def test_write_ansi_keeps_style_and_drops_c1
    @buffer.move(1, 1)
    @buffer.write_ansi("\e[31mR\u009B2J\u0085ed\u202E!")
    assert_equal 'R2Jed!', row
    assert_equal "\e[31m", @buffer.send(:cell_at, 0, 0).sgr
  end

  def test_diff_carries_no_control_byte
    @buffer.move(1, 1)
    @buffer.write("\e]0;owned\a\u009B")
    refute_match(/[\u0000-\u0008\u000E-\u001A\u007F-\u009F]/, @buffer.diff(@blank).gsub(/\e\[[\d;]*[A-Za-z]/, ''))
  end
end
