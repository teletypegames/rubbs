# frozen_string_literal: true

require 'test_helper'

class SelectorTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def items = %w[apple banana cherry].map { |w| Rubbs::Common::Screens::Selector.item(w, key: w[0], value: w.to_sym) }

  def pick(keys, items = self.items, **)
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { Rubbs::Common::Screens::Selector.new(@session, items, width: 30, **).run }
  end

  def test_return_takes_the_lit_item_and_down_moves
    assert_equal :banana, pick("\e[B\r")
  end

  def test_an_items_key_takes_it_at_once
    assert_equal :cherry, pick('c')
  end

  def test_escape_returns_back
    assert_equal :gone, pick("\e\e", back: :gone)
  end

  def test_numbers_light_the_typed_item
    assert_equal :cherry, pick("3\r", numbers: true)
  end

  def test_exits_return_their_value
    assert_equal :quit, pick('q', exits: { 'q' => :quit })
  end

  def test_item_exits_return_their_value_with_the_lit_item
    assert_equal %i[delete banana], pick("\e[BD", item_exits: { 'd' => :delete })
  end

  def test_across_moves_sideways
    assert_equal :banana, pick("\e[C\r", across: true)
  end

  def test_columns_move_sideways_to_the_column_beside
    assert_equal :cherry, pick("\e[C\r", columns: 2)
  end

  def test_pages_turn
    many = (1..10).map { |n| Rubbs::Common::Screens::Selector.item("item #{n}", value: n) }
    assert_equal 4, pick("\e[6~\r", many, height: 3)
  end

  def test_headings_are_never_lit
    list = [Rubbs::Common::Screens::Selector.heading('fruit'), *items]
    assert_equal :apple, pick("\r", list)
  end

  def test_needs_a_selectable_item
    assert_raises(ArgumentError) { Rubbs::Common::Screens::Selector.new(@session, [Rubbs::Common::Screens::Selector.heading('x')], width: 10) }
  end

  def test_the_lit_item_is_a_reversed_bar_in_the_role_colours
    pick("\r")
    shown = @session.received
    assert_includes shown, "#{Rubbs::Petscii::Colors::CY}#{Rubbs::Modern::Ansi::REVERSE} A apple"
    assert_includes shown, "#{Rubbs::Petscii::Colors::YE} B "
  end

  def test_list_numbers_the_objects
    @session.fake_line.caller.write("2\r")
    assert_equal 'two', Timeout.timeout(5) { Rubbs::Common::Screens::Selector.list(@session, %w[one two], width: 20, &:upcase) }
  end
end

class CanvasMenuTest < Minitest::Test
  RawSession = Struct.new(:keys, :raw) do
    def readkey(timeout: nil) = keys.shift || (timeout ? :idle : nil)
    def write_raw(bytes) = raw << bytes
  end

  def test_paints_the_menu_on_the_canvas_and_takes_a_key
    canvas  = Rubbs::Petscii::Canvas.new
    session = RawSession.new(%i[down enter], [])
    selector = Rubbs::Common::Screens::Selector
    items   = [selector.item('ONE', key: '1', value: 1), selector.item('TWO', key: '2', value: 2)]
    menu    = Rubbs::Petscii::CanvasMenu.new(session, items, canvas: canvas, row: 2, col: 1, width: 20)
    assert_equal 2, menu.run
    assert_equal Rubbs::Petscii::Canvas::CYAN, canvas.cell(3, 1).color
    assert canvas.cell(3, 1).rvs
    refute_empty session.raw
  end

  def test_the_idle_block_animates_while_waiting
    session = RawSession.new([], [])
    ticks = 0
    session.define_singleton_method(:readkey) { |**| (ticks += 1) < 3 ? :idle : :enter }
    menu = Rubbs::Petscii::CanvasMenu.new(
      session,
      [Rubbs::Common::Screens::Selector.item('GO', value: :go)],
      canvas: Rubbs::Petscii::Canvas.new,
      row:    0,
      col:    0,
      width:  10,
      idle:   0.1
    ) { 'x' }
    assert_equal :go, menu.run
    assert_includes session.raw, 'x'
  end
end

class PetsciiGlyphsTest < Minitest::Test
  def test_rounded_corners_are_rounded_on_the_canvas_and_square_in_the_lowercase_set
    assert_equal 0xd5, Rubbs::Petscii::Canvas.code('╭').first
    assert_equal Rubbs::Petscii::Glyphs::GRAPHICS['┌'], Rubbs::Petscii::Glyphs::GLYPHS['╭'].ord
    assert_equal 0xb0, Rubbs::Petscii::Canvas.code('┌').first
  end

  def test_palette_colours_turn_into_canvas_codes
    assert_equal Rubbs::Petscii::Canvas::YELLOW, Rubbs::Petscii::Canvas.color(Rubbs::Petscii::Colors::YE)
    assert_equal Rubbs::Petscii::Canvas::GREY, Rubbs::Petscii::Canvas.color(Rubbs::Petscii::Colors::GR)
  end

  def test_plain_spells_typography_in_ascii
    assert_equal 'Aero - "cafe"...', Rubbs::Petscii.plain('Ærø – “café”…')
  end
end
