# frozen_string_literal: true

require 'test_helper'

class EventTest < Minitest::Test
  def test_char_is_printable_only
    assert BBS::Event.key('a').char?
    assert BBS::Event.key('é').char?
    refute BBS::Event.key("\u0085").char?
    refute BBS::Event.key("\u202E").char?
    refute BBS::Event.key("\e").char?
    refute BBS::Event.key(:enter).char?
    refute BBS::Event.idle.char?
  end

  def test_text_buffer_takes_printable_only_up_to_the_cap
    buffer = BBS::TextBuffer.new('', max: 3)
    ["\u202E", "\u0085", 'a', 'b', 'c', 'd'].each { |k| buffer.edit(k) }
    assert_equal 'abc', buffer.text
  end

  def test_text_buffer_default_cap
    buffer = BBS::TextBuffer.new('x' * BBS::TextBuffer::MAX_LENGTH)
    buffer.edit('y')
    assert_equal BBS::TextBuffer::MAX_LENGTH, buffer.length
  end
end
