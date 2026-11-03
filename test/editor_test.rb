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

class EditorAutosaveTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @saves   = []
  end

  def teardown = @session.fake_line.close

  def caller = @session.fake_line.caller

  def editor(text: '', every: 0.1, &block)
    block ||= ->(t) { @saves << t }
    BBS::Editor.new(@session, text: text, cols: 20, rows: 8, autosave: every, &block)
  end

  def run_with(editor)
    Timeout.timeout(5) { editor.run }
  end

  def test_hands_the_changed_text_over_while_the_caller_thinks
    caller.write('ab')
    Thread.new do
      sleep 0.3
      caller.write("\eOP")
    end
    assert_equal 'ab', run_with(editor)
    assert_equal ['ab'], @saves
  end

  def test_saves_while_the_caller_types_without_a_pause
    writer = Thread.new do
      8.times do |i|
        caller.write(i.to_s)
        sleep 0.03
      end
      caller.write("\eOP")
    end
    assert_equal '01234567', run_with(editor)
    writer.join
    refute_empty @saves
    assert(@saves.all? { |t| '01234567'.start_with?(t) })
  end

  def test_an_unchanged_text_is_not_handed_over
    Thread.new do
      sleep 0.3
      caller.write("\eOP")
    end
    assert_equal 'same', run_with(editor(text: 'same'))
    assert_empty @saves
  end

  def test_a_hang_up_hands_over_the_last_text
    caller.write('xy')
    Thread.new do
      sleep 0.05
      caller.close
    end
    assert_raises(IOError, Errno::ECONNRESET, Errno::EPIPE) { run_with(editor(every: 10)) }
    assert_equal ['xy'], @saves
  end

  def test_keeps_the_idle_limit_of_the_session
    @session.idle_seconds = 0.2
    caller.write('z')
    assert_raises(IO::TimeoutError) { run_with(editor(every: 0.05)) }
    assert_equal ['z'], @saves
  end

  def test_a_failing_block_does_not_stop_the_editing
    Thread.new do
      caller.write('k')
      sleep 0.3
      caller.write("\eOP")
    end
    _, err = capture_io { assert_equal 'k', run_with(editor { raise 'disk full' }) }
    assert_includes err, 'editor autosave'
  end

  def test_no_block_means_no_autosave
    caller.write("q\eOP")
    assert_equal 'q', Timeout.timeout(5) { BBS::Editor.new(@session, cols: 20, rows: 8, autosave: 0.01).run }
  end
end
