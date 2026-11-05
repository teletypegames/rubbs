# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

# The modern face of the kit: the look, the tabs going round, an action tab.
class KitModernTest < Minitest::Test
  Kit = Rubbs::Modern::Kit

  # A page of one line.
  class Page < Kit::Screen
    key(:tab) { pages.switch }
    key(:left) { pages.switch(-1) }
    key('q') { quit }

    def initialize(name)
      super()
      @name = name
    end

    def lines = [*masthead(@name), crumbs(@name.to_s.upcase, 'right')]
  end

  def test_the_tabs_go_round_and_an_action_comes_back
    look = Kit::Look.new(logo: ['LOGO'], tabs: { a: 'AAA', b: 'BBB', me: 'ME' }, crumb: 'BOARD', accent: Kit::Palette::YELLOW)
    ran = []
    line = Rubbs::Test::Session.new(keys: [:tab, :tab, :left, 'q'])
    tabs = Kit::Tabs.new(line, look: look, sides: { a: Page.new(:a), b: Page.new(:b) }, actions: { me: ->(t) { ran << t.side } })
    assert_nil tabs.run
    assert_equal [:b], ran
    assert_equal :a, tabs.side
    out = line.output
    assert_includes out, 'LOGO'
    assert_includes out, 'BOARD › A'
    assert_includes out, "#{Kit::Palette::YELLOW}LOGO"
  end

  def test_a_screen_without_a_runner_has_the_default_look
    page = Kit::Lines.new(['x'])
    assert_equal Kit::DEFAULT, page.look
  end
end
