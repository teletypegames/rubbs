# frozen_string_literal: true

require_relative 'test_helper'

class CanvasTest < Minitest::Test
  Canvas = BBS::Petscii::Canvas

  def test_the_lower_set_keeps_the_case_of_text
    canvas = Canvas.new(charset: :lower).text(0, 0, 'Abc Z', :white)
    assert_equal([0xc1, 0x42, 0x43, 0x20, 0xda], (0..4).map { |c| canvas.cell(0, c).code })
    assert_equal 'Abc Z', canvas.to_s.lines.first.chomp
    assert_equal :lower, canvas.charset
  end

  def test_the_upper_set_shows_capitals
    canvas = Canvas.new.text(0, 0, 'Abc', :white)
    assert_equal([0x41, 0x42, 0x43], (0..2).map { |c| canvas.cell(0, c).code })
    assert_equal 'ABC', canvas.to_s.lines.first.chomp
  end

  def test_the_graphics_the_lower_set_has_not_are_question_marks
    assert_equal [0xc0, false], Canvas.code('─', :lower)
    assert_equal ['?'.ord, false], Canvas.code('●', :lower)
    assert_equal [0xd1, false], Canvas.code('●')
    assert Canvas.glyph?('a', :lower)
    refute Canvas.glyph?('●', :lower)
    assert_equal 'Cafe *', Canvas.plain('Café ●', :lower)
  end

  def test_a_frame_switches_to_its_set
    assert_equal Canvas::LOWERCASE, Canvas.new(charset: :lower).frame.getbyte(0)
    assert_equal Canvas::UPPERCASE, Canvas.new.frame.getbyte(0)
    assert_raises(ArgumentError) { Canvas.new(charset: :greek) }
  end

  def test_feeding_a_lower_frame_reads_it_back
    shown = Canvas.new.feed(Canvas.new(charset: :lower).text(2, 3, 'Node 2', :grey).frame)
    assert_equal :lower, shown.charset
    assert_equal 'Node 2', shown.to_s.lines[2].strip
  end

  def test_the_diff_repaints_exactly_what_changed
    before = Canvas.new(charset: :lower).text(3, 1, 'Old text', :green).text(10, 30, 'Side', :cyan)
    after = before.dup.text(3, 1, 'New', :white).text(12, 5, 'Lower', :yellow, rvs: true).text(10, 39, 'X', :red)
    screen = Canvas.new.feed(before.frame)
    screen.feed(after.diff(before))
    assert_empty after.changes(screen)
    assert_equal ''.b, after.diff(after.dup)
  end

  def test_the_row_order_is_cheaper_for_a_block_of_text
    before = Canvas.new(charset: :lower)
    10.times { |r| before.text(4 + r, 0, "Row #{r}".ljust(39), :white) }
    after = before.dup.text(5, 0, '01 Lit row'.ljust(40), :light_blue, rvs: true).text(6, 0, '02 Plain'.ljust(39), :white)
    changed = after.changes(before)
    assert_operator after.patch(changed, order: :rows).bytesize, :<=, after.patch(changed).bytesize
    assert_operator after.diff(before).bytesize, :<, after.frame.bytesize
    assert_raises(ArgumentError) { after.patch(changed, order: :random) }
  end

  def test_the_patch_in_row_order_plays_back
    before = Canvas.new.text(0, 0, 'HELLO', :white)
    after = before.dup.text(0, 0, 'JELLY', :white).text(20, 39, 'Z', :red)
    screen = Canvas.new.feed(before.frame).feed(after.patch(after.changes(before), order: :rows))
    assert_empty after.changes(screen)
  end

  # A terminal that emulates a C64 (bbs-web's xterm.js) waits at the end of a
  # full row instead of going to the next one: after the last cell of a row
  # only printing on may follow, any other move starts from HOME.
  def test_after_the_last_column_the_cursor_goes_from_home
    before = Canvas.new(charset: :lower)
    before.text(4, 0, 'x' * Canvas::COLS, :white, rvs: true)
    after = before.dup
    after.text(4, 0, 'y' * Canvas::COLS, :white)
    after.text(9, 1, 'below', :grey)
    bytes = after.diff(before).bytes
    last = bytes.rindex(Canvas::HOME)
    assert_operator last, :>, bytes.index(Canvas::HOME)
    assert_equal Canvas::DOWN, bytes[last + 1]
  end

  def test_a_full_row_over_an_empty_one_goes_on_from_home
    canvas = Canvas.new(charset: :lower)
    canvas.text(0, 0, '#' * Canvas::COLS, :cyan)
    canvas.text(2, 1, 'third', :white)
    bytes = canvas.frame.bytes
    refute_includes bytes, Canvas::CR
    assert_equal 'third', Canvas.new.feed(canvas.frame).to_s.lines[2].strip
  end
end
