# frozen_string_literal: true

require 'test_helper'

class FrameBufferTest < Minitest::Test
  def setup
    @buffer = BBS::FrameBuffer.new(20, 2)
    @blank  = BBS::FrameBuffer.new(20, 2)
  end

  def row(buffer = @buffer) = (0...20).map { |c| buffer.send(:cell_at, 0, c).char }.join.rstrip

  def test_clip_drops_what_is_written_outside_it
    frame = BBS::FrameBuffer.new(6, 3)
    frame.clip(2, 2, 3, 1) do
      frame.move(1, 1)
      frame.write('abcdef')
      frame.move(1, 2)
      frame.write('abcdef')
    end
    frame.move(1, 3)
    frame.write('after')
    assert_equal ['      ', ' bcd  ', 'after '], rows(frame)
  end

  def test_nested_clips_meet
    frame = BBS::FrameBuffer.new(6, 1)
    frame.clip(1, 1, 4, 1) { frame.clip(3, 1, 4, 1) { frame.move(1, 1).then { frame.write('abcdef') } } }
    assert_equal ['  cd  '], rows(frame)
  end

  def rows(frame) = (0...frame.rows).map { |r| (0...frame.cols).map { |c| frame.send(:cell_at, r, c).char }.join }

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
