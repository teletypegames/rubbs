# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

# The C64 face of the kit: the chrome as configured, the focus going from
# the content to the sub-menu and the tabs, hotkeys, back.
class KitPetsciiTest < Minitest::Test
  Kit = Rubbs::Petscii::Kit
  Canvas = Rubbs::Petscii::Canvas

  # A board of two tabs; the second has a sub-menu.
  class Board < Kit::Frame
    def section_view(key)
      @views ||= {}
      @views[key] ||= case key
                      when :news then Kit::TextView.new('NEWS', ['Today'], color: Canvas::YELLOW, section: :news)
                      when :files, :top then files(key)
                      when :help then Kit::TextView.new('HELP', ['Keys'], color: Canvas::WHITE, section: :help)
                      end
    end

    def action?(key) = key == :me

    def action(key) = (@acted ||= []) << key

    attr_reader :acted

    def top_line(canvas) = chrome.line(canvas, [['3 news', Canvas::WHITE]])

    private

    def files(key)
      entries = %w[a b].map { |n| Kit::MenuView::Entry.new(name: n, count: 1, about: [n], action: -> {}) }
      Kit::MenuView.new(entries, title: key.to_s.upcase, color: Canvas::ORANGE, section: key)
    end
  end

  def chrome
    Kit::Chrome.new(
      title:    'BOARD',
      places:   [[:news, 'NEWS'], [:files, 'FILES'], [:me, 'ME']],
      menu:     [[:files, 'All'], [:top, 'Top']],
      menu_tab: :files,
      hotkeys:  { 'h' => :help, 'q' => :quit }
    )
  end

  def board(keys = []) = Board.new(@line = Rubbs::Test::Session.new(keys: keys, petscii: true), chrome: chrome)

  def shown = Canvas.new.feed(@line.take)

  def test_the_chrome_lays_out_the_places_and_the_menu
    c = chrome
    assert_equal [9, 16, 24], c.places.map(&:col)
    assert_equal [0, 4], c.menu.map(&:col)
    assert_equal({ 'h' => :help, 'q' => :quit, 'a' => :files, 't' => :top }, c.hotkeys)
    assert_equal Kit::Chrome::COLORS[:lit], Kit::Chrome.new(title: '', places: []).colors[:lit]
  end

  def test_the_tabs_switch_with_the_cursor
    b = board
    b.start
    screen = shown
    assert_includes screen.to_s.lines[0], 'BOARD'
    assert_includes screen.to_s.lines[1], '3 news'
    b.press(:up)
    assert_equal :bar, b.focus
    b.press(:right)
    assert_equal %i[files bar], [b.tab, b.focus]
    b.press(:right)
    assert_equal :files, b.tab
    b.press(:enter)
    assert_equal [:me], b.acted
    b.press(:left)
    b.press(:down)
    assert_equal %i[files main], [b.tab, b.focus]
  end

  def test_the_sub_menu_and_the_hotkeys
    b = board
    b.start
    b.press('a')
    assert_equal :files, b.tab
    b.press(:up)
    assert_equal :menu, b.focus
    b.press(:right)
    b.press(:enter)
    assert_equal 'TOP', b.view.title
    b.press(:up)
    b.press(:up)
    assert_equal :bar, b.focus
    b.press(:down)
    b.press('h')
    assert_equal :files, b.tab
    assert_match(/\A HELP /, Canvas.new.feed(@line.take).to_s.lines[3])
  end

  def test_back_goes_home_then_ends
    b = board(['a', :escape, :escape])
    assert_nil b.run
    assert_equal :news, b.tab
  end
end
