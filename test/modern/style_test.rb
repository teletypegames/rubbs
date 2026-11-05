# frozen_string_literal: true

require_relative '../test_helper'

class StyleTest < Minitest::Test
  def test_a_style_is_its_sgr_sequence
    assert_equal "\e[38;5;84m", Rubbs::Modern::Style[fg: 84]
    assert_equal "\e[1;38;5;84;48;5;235m", Rubbs::Modern::Style[fg: 84, bg: 235, bold: true]
    assert_equal "\e[1;91m", Rubbs::Modern::Style[fg: :bright_red, bold: true]
    assert_equal "\e[32;44m", Rubbs::Modern::Style[fg: :green, bg: 'blue']
    assert_equal "\e[38;2;1;2;3m", Rubbs::Modern::Style[fg: [1, 2, 3]]
    assert_equal '', Rubbs::Modern::Style[]
    assert_predicate Rubbs::Modern::Style[fg: 1], :frozen?
  end

  def test_a_style_paints_and_resets
    assert_equal "\e[38;5;1mhi\e[0m", Rubbs::Modern::Style.paint(Rubbs::Modern::Style[fg: 1], 'hi')
  end

  def test_unknown_parts_raise
    assert_raises(ArgumentError) { Rubbs::Modern::Style[fg: 300] }
    assert_raises(ArgumentError) { Rubbs::Modern::Style[fg: :mauve] }
    assert_raises(ArgumentError) { Rubbs::Modern::Style[sparkle: true] }
  end
end

class NodesTest < Minitest::Test
  def test_each_call_gets_the_lowest_free_node
    nodes = Rubbs::Common::Line::Nodes.new
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
