# frozen_string_literal: true

require 'test_helper'

class FieldTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def type(keys, **)
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { Rubbs::Common::Screens::Field.new(@session, width: 6, **).run }
  end

  def test_edits_from_the_text_and_returns_it
    assert_equal 'Xabcd!', type("\e[H\X\e[F!\r", text: 'abcd')
  end

  def test_cancel_returns_nil
    assert_nil type("x\x03", text: 'a')
  end

  def test_scrolls_and_masks
    type("\r", text: 'abcdefgh', mask: '*')
    assert_includes @session.received, '*****'
    refute_includes @session.received, 'abc'
  end

  def test_ask_fits_the_rest_of_the_line
    @session.fake_line.caller.write("hi\r")
    assert_equal 'hi', Timeout.timeout(5) { Rubbs::Common::Screens::Field.ask(@session, "line\r\nname> ", max: 5) }
  end
end

class TextBufferTest < Minitest::Test
  def test_edits_and_tells_the_keys_it_takes
    buffer = Rubbs::Common::Screens::TextBuffer.new("ab\ncd", max: 10)
    assert_same buffer, buffer.edit(:left)
    assert_same buffer, buffer.edit(:enter)
    assert_same buffer, buffer.edit(:backspace)
    assert_same buffer, buffer.edit(:delete)
    assert_nil buffer.edit(:f1)
    assert_equal "ab\nc", buffer.text
    buffer.place(0, 0)
    buffer.edit(:backspace)
    buffer.edit(:right)
    buffer.edit("\e")
    assert_equal "ab\nc", buffer.text
  end

  def test_single_line_takes_no_return_and_max_holds
    buffer = Rubbs::Common::Screens::TextBuffer.new("a\tb\nc", max: 5, single_line: true)
    assert_equal 'a b c', buffer.text
    assert_nil buffer.edit(:enter)
    buffer.edit('x')
    assert_equal 'a b c', buffer.text
  end
end
