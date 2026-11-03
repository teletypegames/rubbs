# frozen_string_literal: true

require_relative 'test_helper'

class StyleTest < Minitest::Test
  def test_a_style_is_its_sgr_sequence
    assert_equal "\e[38;5;84m", BBS::Style[fg: 84]
    assert_equal "\e[1;38;5;84;48;5;235m", BBS::Style[fg: 84, bg: 235, bold: true]
    assert_equal "\e[1;91m", BBS::Style[fg: :bright_red, bold: true]
    assert_equal "\e[32;44m", BBS::Style[fg: :green, bg: 'blue']
    assert_equal "\e[38;2;1;2;3m", BBS::Style[fg: [1, 2, 3]]
    assert_equal '', BBS::Style[]
    assert_predicate BBS::Style[fg: 1], :frozen?
  end

  def test_a_style_paints_and_resets
    assert_equal "\e[38;5;1mhi\e[0m", BBS::Style.paint(BBS::Style[fg: 1], 'hi')
  end

  def test_unknown_parts_raise
    assert_raises(ArgumentError) { BBS::Style[fg: 300] }
    assert_raises(ArgumentError) { BBS::Style[fg: :mauve] }
    assert_raises(ArgumentError) { BBS::Style[sparkle: true] }
  end
end

class NodesTest < Minitest::Test
  def test_each_call_gets_the_lowest_free_node
    nodes = BBS::Nodes.new
    seen = []
    nodes.take do |a|
      nodes.take do |b|
        seen << a << b
        assert_equal [1, 2], nodes.taken
      end
      nodes.take { |c| seen << c }
    end
    assert_equal [1, 2, 2], seen
    assert_empty nodes.taken
    boom = ->(_node) { raise 'boom' }
    assert_raises(RuntimeError) { nodes.take(&boom) }
    assert_empty nodes.taken
  end
end
