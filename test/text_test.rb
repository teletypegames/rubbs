# frozen_string_literal: true

require 'test_helper'

class TextTest < Minitest::Test
  def test_clean_removes_controls_and_bidi
    assert_equal "Ada[2Jtxt.exe\n\tx", BBS::Text.clean("Ada\e[2J\u202Etxt.exe\u0085\u2066\r\n\tx\u007F")
  end

  def test_clean_scrubs_invalid_utf8
    assert_equal 'Bob', BBS::Text.clean("Bo\xFFb".b)
  end

  def test_clean_without_newlines
    assert_equal "ab\tc", BBS::Text.clean("a\nb\tc", keep_newlines: false)
  end

  def test_clean_takes_anything
    assert_equal '42', BBS::Text.clean(42)
    assert_equal '', BBS::Text.clean(nil)
  end

  def test_printable
    %w[a é 漢 ★].each { |c| assert BBS::Text.printable?(c), c }
    ["\e", "\u0085", "\u202E", "\u2067", "\t", 'ab', :a, nil].each { |c| refute BBS::Text.printable?(c), c.inspect }
  end
end
