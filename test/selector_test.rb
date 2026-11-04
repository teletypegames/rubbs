# frozen_string_literal: true

require 'test_helper'

class SelectorTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def items = %w[apple banana cherry].map { |w| BBS::Selector.item(w, key: w[0], value: w.to_sym) }

  def pick(keys, items = self.items, **)
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { BBS::Selector.new(@session, items, width: 30, **).run }
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
    many = (1..10).map { |n| BBS::Selector.item("item #{n}", value: n) }
    assert_equal 4, pick("\e[6~\r", many, height: 3)
  end

  def test_headings_are_never_lit
    list = [BBS::Selector.heading('fruit'), *items]
    assert_equal :apple, pick("\r", list)
  end

  def test_needs_a_selectable_item
    assert_raises(ArgumentError) { BBS::Selector.new(@session, [BBS::Selector.heading('x')], width: 10) }
  end

  def test_the_lit_item_is_a_reversed_bar_in_the_role_colours
    pick("\r")
    shown = @session.received
    assert_includes shown, "#{BBS::Petscii::Colors::CY}#{BBS::Ansi::REVERSE} A apple"
    assert_includes shown, "#{BBS::Petscii::Colors::YE} B "
  end

  def test_list_numbers_the_objects
    @session.fake_line.caller.write("2\r")
    assert_equal 'two', Timeout.timeout(5) { BBS::Selector.list(@session, %w[one two], width: 20, &:upcase) }
  end
end

class CanvasMenuTest < Minitest::Test
  RawSession = Struct.new(:keys, :raw) do
    def readkey(timeout: nil) = keys.shift || (timeout ? :idle : nil)
    def write_raw(bytes) = raw << bytes
  end

  def test_paints_the_menu_on_the_canvas_and_takes_a_key
    canvas  = BBS::Petscii::Canvas.new
    session = RawSession.new(%i[down enter], [])
    items   = [BBS::Selector.item('ONE', key: '1', value: 1), BBS::Selector.item('TWO', key: '2', value: 2)]
    menu    = BBS::Petscii::CanvasMenu.new(session, items, canvas: canvas, row: 2, col: 1, width: 20)
    assert_equal 2, menu.run
    assert_equal BBS::Petscii::Canvas::CYAN, canvas.cell(3, 1).color
    assert canvas.cell(3, 1).rvs
    refute_empty session.raw
  end

  def test_the_idle_block_animates_while_waiting
    session = RawSession.new([], [])
    ticks = 0
    session.define_singleton_method(:readkey) { |**| (ticks += 1) < 3 ? :idle : :enter }
    menu = BBS::Petscii::CanvasMenu.new(
      session,
      [BBS::Selector.item('GO', value: :go)],
      canvas: BBS::Petscii::Canvas.new,
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
    assert_equal 0xd5, BBS::Petscii::Canvas.code('╭').first
    assert_equal BBS::Petscii::GRAPHICS['┌'], BBS::Petscii::GLYPHS['╭'].ord
    assert_equal 0xb0, BBS::Petscii::Canvas.code('┌').first
  end

  def test_palette_colours_turn_into_canvas_codes
    assert_equal BBS::Petscii::Canvas::YELLOW, BBS::Petscii::Canvas.color(BBS::Petscii::Colors::YE)
    assert_equal BBS::Petscii::Canvas::GREY, BBS::Petscii::Canvas.color(BBS::Petscii::Colors::GR)
  end

  def test_plain_spells_typography_in_ascii
    assert_equal 'Aero - "cafe"...', BBS::Petscii.plain('Ærø – “café”…')
  end
end
