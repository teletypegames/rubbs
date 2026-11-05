# frozen_string_literal: true

require 'test_helper'

class TextTest < Minitest::Test
  def test_clean_removes_controls_and_bidi
    assert_equal "Ada[2Jtxt.exe\n\tx", Rubbs::Common::Text.clean("Ada\e[2J\u202Etxt.exe\u0085\u2066\r\n\tx\u007F")
  end

  def test_clean_scrubs_invalid_utf8
    assert_equal 'Bob', Rubbs::Common::Text.clean("Bo\xFFb".b)
  end

  def test_clean_without_newlines_keeps_the_words_apart
    assert_equal "a b\tc d e", Rubbs::Common::Text.clean("a\nb\tc\r\nd\re", keep_newlines: false)
  end

  def test_line
    assert_equal 'Ada Lovelace [2J', Rubbs::Common::Text.line("  Ada\r\n\tLovelace  \e[2J\n")
    assert_equal '', Rubbs::Common::Text.line(nil)
  end

  def test_clean_takes_anything
    assert_equal '42', Rubbs::Common::Text.clean(42)
    assert_equal '', Rubbs::Common::Text.clean(nil)
  end

  def test_printable
    %w[a é 漢 ★].each { |c| assert Rubbs::Common::Text.printable?(c), c }
    ["\e", "\u0085", "\u202E", "\u2067", "\t", 'ab', :a, nil].each { |c| refute Rubbs::Common::Text.printable?(c), c.inspect }
  end
end
