# frozen_string_literal: true

require 'test_helper'
require 'json'
require_relative '../fixtures/markdown_corpus'

class MarkdownTest < Minitest::Test
  EXPECTED = JSON.parse(File.read(File.join(__dir__, '../fixtures/markdown_expected.json')))
  TAGS = { text: '<t>', text_bright: '<B>', text_dim: '<d>', accent: '<a>', label: '<l>' }.freeze

  def lines(text, width: 40) = Rubbs::Common::Text::Markdown.to_lines(text, width: width, theme: TAGS)

  def test_renders_the_corpus_as_before
    MARKDOWN_CORPUS.each do |name, text|
      [20, 40, 80].each do |w|
        assert_equal EXPECTED["#{name}/#{w}/theme"],
                     Rubbs::Common::Text::Markdown.to_lines(text, width: w, theme: Rubbs::Modern::Theme.synchronet),
                     "#{name} at #{w} (theme)"
        assert_equal EXPECTED["#{name}/#{w}/hash"], lines(text, width: w), "#{name} at #{w} (hash)"
      end
    end
  end

  def test_headings_take_their_level_style
    assert_equal ['<B>Top<t>', '<a>Two<t>', '<l>Three<t>'], lines("# Top\n## Two\n### Three")
  end

  def test_inline_spans_end_in_the_text_style
    assert_equal ['<B>bold<t> <d>it<t> <l>code<t> <a>link<t>'], lines('**bold** *it* `code` [link](u)', width: 80)
  end

  def test_bullets_and_numbers
    assert_equal ['<a>•<t> one', '  <a>3.<t> three'], lines("- one\n  3. three")
  end

  def test_a_rule_fills_the_width
    assert_equal ["<l>#{'─' * 10}<t>"], lines('---', width: 10)
  end

  def test_code_is_clipped_not_wrapped
    assert_equal ['<l>abcde<t>'], lines("```\nabcdefgh\n```", width: 5)
  end

  def test_a_table_is_boxed_with_aligned_cells
    out = lines("|a|b|\n|-|-:|\n|x|10|")
    assert_equal '<l>┌───┬────┐<t>', out.first
    assert_equal '<l>│<t> x <l>│<t> 10 <l>│<t>', out[3]
  end
end
