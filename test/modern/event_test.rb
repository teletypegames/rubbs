# frozen_string_literal: true

require 'test_helper'

class EventTest < Minitest::Test
  def test_char_is_printable_only
    assert Rubbs::Modern::Widgets::Event.key('a').char?
    assert Rubbs::Modern::Widgets::Event.key('é').char?
    refute Rubbs::Modern::Widgets::Event.key("\u0085").char?
    refute Rubbs::Modern::Widgets::Event.key("\u202E").char?
    refute Rubbs::Modern::Widgets::Event.key("\e").char?
    refute Rubbs::Modern::Widgets::Event.key(:enter).char?
    refute Rubbs::Modern::Widgets::Event.idle.char?
  end

  def test_text_buffer_takes_printable_only_up_to_the_cap
    buffer = Rubbs::Common::Screens::TextBuffer.new('', max: 3)
    ["\u202E", "\u0085", 'a', 'b', 'c', 'd'].each { |k| buffer.edit(k) }
    assert_equal 'abc', buffer.text
  end

  def test_text_buffer_default_cap
    buffer = Rubbs::Common::Screens::TextBuffer.new('x' * Rubbs::Common::Screens::TextBuffer::MAX_LENGTH)
    buffer.edit('y')
    assert_equal Rubbs::Common::Screens::TextBuffer::MAX_LENGTH, buffer.length
  end
end
