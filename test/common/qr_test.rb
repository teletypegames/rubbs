# frozen_string_literal: true

require 'test_helper'

class QRTest < Minitest::Test
  URL = 'https://teletypegames.org/blog/hello-world-from-feedia?x=1'
  HALF = { '█' => [false, false], '▀' => [false, true], '▄' => [true, false], ' ' => [true, true] }.freeze

  def test_modules_take_the_smallest_version
    assert_equal 21, Rubbs::Common::Text::QR.modules('TTG').size
    assert_equal 33, Rubbs::Common::Text::QR.modules(URL).size
  end

  def test_too_long_for_the_room
    assert_raises(Rubbs::Common::Text::QR::TooLong) { Rubbs::Common::Text::QR.modules('x' * 100, max_version: 2) }
    assert_raises(Rubbs::Common::Text::QR::TooLong) { Rubbs::Common::Text::QR.petscii('x' * 200) }
    assert_raises(Rubbs::Common::Text::QR::TooLong) { Rubbs::Common::Text::QR.ansi('TTG', width: 20) }
  end

  def test_ansi_draws_the_modules_in_half_blocks
    lines = Rubbs::Common::Text::QR.ansi(URL)
    assert_equal(framed(Rubbs::Common::Text::QR.modules(URL)), lines.flat_map { |l| unhalf(l) })
    assert(lines.all? { |l| l.start_with?(Rubbs::Common::Text::QR::PEN) && l.end_with?(Rubbs::Modern::Ansi::RESET) })
  end

  def test_petscii_draws_the_modules_in_quadrants
    lines = Rubbs::Common::Text::QR.petscii(URL)
    assert_equal(framed(Rubbs::Common::Text::QR.modules(URL)), lines.flat_map { |l| unquad(l) })
  end

  def test_petscii_fits_the_c64_screen
    lines = Rubbs::Common::Text::QR.petscii(URL)
    assert_operator lines.size, :<=, Rubbs::Petscii::ROWS - 5
    assert(lines.all? { |l| Rubbs::Modern::FrameBuffer.plain(l).size < Rubbs::Petscii::COLS })
  end

  def test_petscii_has_a_c64_glyph_for_every_cell
    bytes = Rubbs::Common::Text::QR.petscii(URL).map { |l| Rubbs::Petscii::Encoder.new.encode(l) }.join.bytes.uniq
    assert_empty bytes - [0x05, 0x12, 0x92, 0x20, 0x9b, 0xa1, 0xa2, 0xac, 0xbb, 0xbc, 0xbe, 0xbf]
  end

  private

  def framed(core)
    side  = core.size + (2 * Rubbs::Common::Text::QR::QUIET) + 1
    blank = Array.new(side, false)
    rows  = core.map { |r| [false, false, *r, false, false, false] }
    [blank, blank, *rows, blank, blank, blank]
  end

  def unhalf(line)
    pairs = Rubbs::Modern::FrameBuffer.plain(line).chars.map { |c| HALF.fetch(c) }
    [pairs.map(&:first), pairs.map(&:last)]
  end

  def unquad(line)
    codes = Rubbs::Common::Text::QR::QUADRANTS.invert
    body  = line.delete_prefix(Rubbs::Common::Text::QR::PEN).delete_suffix(Rubbs::Modern::Ansi::RESET)
    masks = body.scan(/\e\[7m([^\e]+)\e\[27m|([^\e])/).flat_map do |rvs, plain|
      rvs ? rvs.chars.map { |c| Rubbs::Common::Text::QR::FULL ^ codes.fetch(c) } : [codes.fetch(plain)]
    end
    [masks.flat_map { |m| [m & 8, m & 4] }, masks.flat_map { |m| [m & 2, m & 1] }].map { |r| r.map(&:zero?) }
  end
end
