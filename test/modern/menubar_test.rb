# frozen_string_literal: true

require 'test_helper'

class MenubarTest < Minitest::Test
  Mouse = Struct.new(:kind, :button, :x, :y)

  def setup
    @chosen = []
    @bar = Rubbs::Modern::Menubar.new(theme: Rubbs::Modern::Theme.mono)
    @bar.layout(1, 1, 40, 1)
    items = [item('&Open', 'F3'), separator, item('E&xit', nil, :halt)]
    @bar.menus << Rubbs::Modern::Menubar::Menu.new(label: '&File', items: items)
    @bar.menus << Rubbs::Modern::Menubar::Menu.new(label: '&Edit', items: [item('&Copy'), item('&Paste', enabled: false)])
  end

  def item(label, shortcut = nil, result = nil, enabled: true)
    Rubbs::Modern::Menubar::MenuItem.new(
      label:     label,
      shortcut:  shortcut,
      enabled:   enabled,
      separator: false,
      on_select: ->(i) { @chosen << i.display; result }
    )
  end

  def separator = Rubbs::Modern::Menubar::MenuItem.new(label: '', enabled: false, separator: true)

  def key(name) = Rubbs::Modern::Widgets::Event.key(name)
  def click(x, y) = Rubbs::Modern::Widgets::Event.mouse(Mouse.new(:press, :left, x, y))

  def frame
    f = Rubbs::Modern::FrameBuffer.new(40, 8)
    @bar.render(f)
    f
  end

  def row(f, y) = (0...f.cols).map { |x| f.send(:cell_at, y - 1, x).char }.join.rstrip

  def test_f10_opens_and_keys_move_and_activate
    assert_equal :handled, @bar.handle_event(key(:f10))
    assert_equal 'Open', @bar.selected_item.display
    @bar.handle_event(key(:down))
    assert_equal 'Exit', @bar.selected_item.display
    assert_equal :halt, @bar.handle_event(key(:enter))
    refute @bar.open?
    assert_equal ['Exit'], @chosen
  end

  def test_alt_hotkey_left_right_and_item_hotkey
    @bar.handle_event(key(:alt_e))
    assert_equal 'Edit', @bar.opened_menu.display
    @bar.handle_event(key(:down))
    assert_equal 'Copy', @bar.selected_item.display
    @bar.handle_event(key(:right))
    assert_equal 'File', @bar.opened_menu.display
    assert_equal :handled, @bar.handle_event(key('o'))
    assert_equal ['Open'], @chosen
    assert_nil @bar.handle_event(key('x'))
  end

  def test_escape_closes_and_disabled_items_are_skipped
    @bar.open(1)
    @bar.handle_event(key(:up))
    assert_equal 'Copy', @bar.selected_item.display
    @bar.handle_event(key('p'))
    assert_empty @chosen
    @bar.handle_event(key(:escape))
    refute @bar.open?
  end

  def test_draws_the_bar_and_the_dropdown
    @bar.open(0)
    f = frame
    assert_equal '  File   Edit', row(f, 1)
    assert_equal ' ┌──────────┐', row(f, 2)
    assert_equal ' │ Open   F3│', row(f, 3)
    assert_equal ' │──────────│', row(f, 4)
    assert_equal ' │ Exit     │', row(f, 5)
  end

  def test_mouse_opens_toggles_picks_and_closes
    frame
    @bar.handle_event(click(9, 1))
    assert_equal 'Edit', @bar.opened_menu.display
    @bar.handle_event(click(9, 1))
    refute @bar.open?
    @bar.handle_event(click(3, 1))
    frame
    assert_equal :halt, @bar.handle_event(click(4, 5))
    @bar.open(0)
    assert_equal :handled, @bar.handle_event(click(30, 6))
    refute @bar.open?
    assert_nil @bar.handle_event(click(30, 6))
  end
end
