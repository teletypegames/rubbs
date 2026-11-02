# frozen_string_literal: true

require 'test_helper'

class EditorLayoutTest < Minitest::Test
  def test_wraps_at_word_boundaries
    layout = BBS::Editor::Layout.new(['the quick brown fox', 'x'], 10)
    assert_equal [[0, 0, 10], [0, 10, 19], [1, 0, 1]], layout.rows
    assert_equal 1, layout.row_of(0, 12)
    assert_equal 9, layout.row_end(0)
    assert_equal 19, layout.row_end(1)
  end

  def test_a_long_word_breaks_at_the_width
    assert_equal [[0, 0, 4], [0, 4, 8], [0, 8, 9]], BBS::Editor::Layout.new(['abcdefghi'], 4).rows
  end
end

class EditorTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def edit(keys, **)
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { BBS::Editor.new(@session, cols: 20, rows: 8, **).run }
  end

  def test_types_moves_and_saves_with_f1
    assert_equal "ab\nXcd", edit("ab\rcd\e[A\e[B\e[H\X\eOP", text: '')
  end

  def test_escape_then_q_quits
    assert_nil edit("abc\x11q", text: 'x')
  end

  def test_escape_then_s_saves_and_another_key_goes_back
    assert_equal 'xy', edit("\x11xy\x11s", text: 'x')
  end

  def test_single_line_saves_on_return_and_counts
    assert_equal 'hi there', edit("there\r", text: 'hi ', single_line: true, max: 20)
    assert_includes @session.received, '8/20'
  end

  def test_home_end_and_page_keys
    assert_equal "one\nZtwo three", edit("\e[5~\e[6~\e[H\Z\eOP", text: "one\ntwo three")
  end
end
