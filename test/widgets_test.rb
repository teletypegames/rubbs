# frozen_string_literal: true

require 'test_helper'

module WidgetTestHelpers
  Mouse = Struct.new(:kind, :button, :x, :y)

  def key(name) = BBS::Event.key(name)
  def click(x, y, kind: :press, button: :left) = BBS::Event.mouse(Mouse.new(kind, button, x, y))

  def place(widget, x: 1, y: 1, width: 10, height: 1, focused: true)
    widget.theme = BBS::Theme.mono
    widget.layout(x, y, width, height)
    widget.focused = focused
    widget
  end

  def row(frame, y, from: 1, width: frame.cols) = (from...(from + width)).map { |x| frame.send(:cell_at, y - 1, x - 1).char }.join

  def drawn(widget, cols: 20, rows: 5)
    frame = BBS::FrameBuffer.new(cols, rows)
    widget.render(frame)
    frame
  end
end

class LabelTest < Minitest::Test
  include WidgetTestHelpers

  def test_aligns_and_clips
    assert_equal 'hi        ', row(drawn(place(BBS::Widgets::Label.new(text: 'hi'))), 1, width: 10)
    assert_equal '    hi    ', row(drawn(place(BBS::Widgets::Label.new(text: 'hi', align: :center))), 1, width: 10)
    assert_equal '        hi', row(drawn(place(BBS::Widgets::Label.new(text: 'hi', align: :right))), 1, width: 10)
    assert_equal 'abc', row(drawn(place(BBS::Widgets::Label.new(text: 'abcdef'), width: 3)), 1, width: 3)
  end
end

class ButtonTest < Minitest::Test
  include WidgetTestHelpers

  def test_draws_the_label_with_its_hotkey_and_fires
    clicks = 0
    button = place(BBS::Widgets::Button.new(label: '&Save', on_click: ->(_) { clicks += 1 }), width: 12)
    frame = drawn(button)
    assert_equal '  [ Save ]  ', row(frame, 1, width: 12)
    assert_equal 'b', BBS::Widgets::Button.new(label: 'a&b').hotkey
    assert_equal :handled, button.handle_event(key(:enter))
    assert_equal :handled, button.handle_event(click(2, 1))
    assert_nil button.handle_event(key('x'))
    assert_equal 2, clicks
  end

  def test_halt_and_disabled
    button = place(BBS::Widgets::Button.new(on_click: ->(_) { :halt }))
    assert_equal :halt, button.handle_event(key(' '))
    button.enabled = false
    assert_nil button.handle_event(key(:enter))
  end
end

class TextInputTest < Minitest::Test
  include WidgetTestHelpers

  def input(**) = place(BBS::Widgets::TextInput.new(**), width: 6)

  def test_typing_moving_and_deleting
    changes = []
    field = input(on_change: ->(v, _) { changes << v.dup })
    %w[a b c].each { |c| field.handle_event(key(c)) }
    field.handle_event(key(:left))
    field.handle_event(key(:backspace))
    field.handle_event(key(:home))
    field.handle_event(key(:delete))
    field.handle_event(key(:end))
    field.handle_event(key('z'))
    assert_equal 'cz', field.value
    assert_equal %w[a ab abc ac c cz], changes
  end

  def test_max_length_enter_and_unknown_keys
    submitted = nil
    field = input(max_length: 2, on_submit: ->(v, _) { submitted = v; nil })
    %w[a b c].each { |c| field.handle_event(key(c)) }
    assert_equal 'ab', field.value
    assert_equal :handled, field.handle_event(key(:enter))
    assert_equal 'ab', submitted
    assert_nil field.handle_event(key(:escape))
    assert_nil field.handle_event(click(1, 1))
  end

  def test_scrolls_and_draws_the_cursor
    field = input(value: 'abcdefgh')
    assert_equal 'abcde_', row(drawn(field), 1, width: 6)
    field.handle_event(key(:left))
    field.handle_event(key(:right))
    assert_equal 'efgh_ ', row(drawn(field), 1, width: 6)
    field.handle_event(key(:home))
    assert_equal '_bcde ', row(drawn(field), 1, width: 6)
  end

  def test_placeholder_and_password
    empty = place(BBS::Widgets::TextInput.new(placeholder: 'name'), width: 6, focused: false)
    assert_equal 'name  ', row(drawn(empty), 1, width: 6)
    secret = input(value: 'pw', password: true)
    assert_equal '**_   ', row(drawn(secret), 1, width: 6)
    secret.value = 'xyz'
    assert_equal 'xyz', secret.value
  end
end

class TextAreaTest < Minitest::Test
  include WidgetTestHelpers

  def area(**) = place(BBS::Widgets::TextArea.new(**), width: 8, height: 2)

  def test_typing_enter_and_backspace_join
    text = area
    'ab'.each_char { |c| text.handle_event(key(c)) }
    text.handle_event(key(:left))
    text.handle_event(key(:enter))
    assert_equal "a\nb", text.value
    text.handle_event(key(:backspace))
    assert_equal 'ab', text.value
    text.handle_event(key(:backspace))
    assert_equal 'b', text.value
  end

  def test_cursor_wraps_across_lines_and_scrolls
    text = area(value: "one\ntwo\nthree")
    text.handle_event(key(:end))
    text.handle_event(key(:right))
    text.handle_event(key('X'))
    assert_equal "one\nXtwo\nthree", text.value
    text.handle_event(key(:home))
    text.handle_event(key(:left))
    text.handle_event(key('Y'))
    assert_equal "oneY\nXtwo\nthree", text.value
    2.times { text.handle_event(key(:down)) }
    frame = drawn(text)
    assert_equal 'Xtwo    ', row(frame, 1, width: 8)
    assert_equal 'thre_   ', row(frame, 2, width: 8)
  end

  def test_max_length_and_unknown_keys
    text = area(max_length: 1)
    text.handle_event(key('a'))
    text.handle_event(key('b'))
    assert_equal 'a', text.value
    assert_nil text.handle_event(key(:f1))
    text.handle_event(key(:up))
    assert_equal 'a', text.value
  end
end

class CheckboxTest < Minitest::Test
  include WidgetTestHelpers

  def test_toggles
    seen = nil
    box = place(BBS::Widgets::Checkbox.new(label: 'ok', on_change: ->(c, _) { seen = c }))
    assert_equal '[ ] ok', row(drawn(box), 1, width: 6)
    assert_equal :handled, box.handle_event(key(' '))
    assert seen
    assert_equal '[x] ok', row(drawn(box), 1, width: 6)
    assert_nil box.handle_event(key('a'))
  end
end

class ListBoxTest < Minitest::Test
  include WidgetTestHelpers

  def list(**)
    place(BBS::Widgets::ListBox.new(items: %w[a b c d e], **), width: 4, height: 2)
  end

  def test_keys_move_and_scroll
    picked = []
    box = list(on_select: ->(i, _) { picked << i })
    box.handle_event(key(:down))
    box.handle_event(key(:down))
    assert_equal 1, box.scroll
    box.handle_event(key(:end))
    box.handle_event(key(:page_up))
    box.handle_event(key(:home))
    box.handle_event(key(:up))
    assert_equal %w[b c e c a], picked
    assert_nil box.handle_event(key('x'))
  end

  def test_enter_click_and_wheel
    box = list(on_activate: ->(i, _) { "got #{i}" }, label: :upcase.to_proc)
    assert_equal 'got a', box.handle_event(key(:enter))
    assert_equal :handled, box.handle_event(click(1, 2))
    assert_equal 'b', box.selected_item
    box.handle_event(click(1, 1, kind: :wheel, button: :down))
    assert_equal 'e', box.selected_item
    frame = drawn(box)
    assert_equal 'D   ', row(frame, 1, width: 4)
    assert_equal 'E   ', row(frame, 2, width: 4)
  end
end

class ScrollViewTest < Minitest::Test
  include WidgetTestHelpers

  def test_scrolls_and_draws_a_scrollbar
    view = place(BBS::Widgets::ScrollView.new(lines: %w[1 2 3 4 5]), width: 4, height: 2)
    view.handle_event(key(:end))
    assert_equal 3, view.scroll
    view.handle_event(click(1, 1, kind: :wheel, button: :up))
    assert_equal 0, view.scroll
    view.handle_event(key(:page_down))
    frame = drawn(view)
    assert_equal '3  █', row(frame, 1, width: 4)
    assert_nil view.handle_event(key('x'))
  end
end

class SceneTest < Minitest::Test
  include WidgetTestHelpers

  ART = [
    'size: [4, 2]', 'charset: cp437', 'palette:', '  w: 15',
    'chars: |2', '  ab  ', '  cdef', 'colors: |2', '  wwww', '  wwww',
    'hotspots:', '  spot: [2, 0, 2, 2]'
  ].join("\n")

  def scene(**) = BBS::Widgets::Scene.new(art: BBS::Art.parse(ART), **)

  def test_draws_the_art_centred_and_fills_a_hotspot
    widget = place(scene(align: :center, fills: { spot: ->(_) { "XY\nZ" } }), width: 8, height: 3)
    frame = drawn(widget)
    assert_equal '  abXY  ', row(frame, 1, width: 8)
    assert_equal '  cdZf  ', row(frame, 2, width: 8)
  end

  def test_a_small_bounds_cuts_the_art_or_drops_it
    assert_equal 'ab', row(drawn(place(scene, width: 2, height: 1)), 1, width: 2)
    refute_equal 'a', row(drawn(place(scene(crop: false), width: 2, height: 1)), 1, width: 1)
    assert_raises(BBS::Art::Error) { scene.fill(:nope) { '' } }
  end
end
