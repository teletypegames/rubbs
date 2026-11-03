# frozen_string_literal: true

require 'test_helper'

class QRTest < Minitest::Test
  URL = 'https://teletypegames.org/blog/hello-world-from-feedia?x=1'
  HALF = { '█' => [false, false], '▀' => [false, true], '▄' => [true, false], ' ' => [true, true] }.freeze

  def test_modules_take_the_smallest_version
    assert_equal 21, BBS::QR.modules('TTG').size
    assert_equal 33, BBS::QR.modules(URL).size
  end

  def test_too_long_for_the_room
    assert_raises(BBS::QR::TooLong) { BBS::QR.modules('x' * 100, max_version: 2) }
    assert_raises(BBS::QR::TooLong) { BBS::QR.petscii('x' * 200) }
    assert_raises(BBS::QR::TooLong) { BBS::QR.ansi('TTG', width: 20) }
  end

  def test_ansi_draws_the_modules_in_half_blocks
    lines = BBS::QR.ansi(URL)
    assert_equal(framed(BBS::QR.modules(URL)), lines.flat_map { |l| unhalf(l) })
    assert(lines.all? { |l| l.start_with?(BBS::QR::PEN) && l.end_with?(BBS::Ansi::RESET) })
  end

  def test_petscii_draws_the_modules_in_quadrants
    lines = BBS::QR.petscii(URL)
    assert_equal(framed(BBS::QR.modules(URL)), lines.flat_map { |l| unquad(l) })
  end

  def test_petscii_fits_the_c64_screen
    lines = BBS::QR.petscii(URL)
    assert_operator lines.size, :<=, BBS::Petscii::ROWS - 5
    assert(lines.all? { |l| BBS::FrameBuffer.plain(l).size < BBS::Petscii::COLS })
  end

  def test_petscii_has_a_c64_glyph_for_every_cell
    bytes = BBS::QR.petscii(URL).map { |l| BBS::Petscii::Encoder.new.encode(l) }.join.bytes.uniq
    assert_empty bytes - [0x05, 0x12, 0x92, 0x20, 0x9b, 0xa1, 0xa2, 0xac, 0xbb, 0xbc, 0xbe, 0xbf]
  end

  private

  def framed(core)
    side  = core.size + (2 * BBS::QR::QUIET) + 1
    blank = Array.new(side, false)
    rows  = core.map { |r| [false, false, *r, false, false, false] }
    [blank, blank, *rows, blank, blank, blank]
  end

  def unhalf(line)
    pairs = BBS::FrameBuffer.plain(line).chars.map { |c| HALF.fetch(c) }
    [pairs.map(&:first), pairs.map(&:last)]
  end

  def unquad(line)
    codes = BBS::QR::QUADRANTS.invert
    body  = line.delete_prefix(BBS::QR::PEN).delete_suffix(BBS::Ansi::RESET)
    masks = body.scan(/\e\[7m([^\e]+)\e\[27m|([^\e])/).flat_map do |rvs, plain|
      rvs ? rvs.chars.map { |c| BBS::QR::FULL ^ codes.fetch(c) } : [codes.fetch(plain)]
    end
    [masks.flat_map { |m| [m & 8, m & 4] }, masks.flat_map { |m| [m & 2, m & 1] }].map { |r| r.map(&:zero?) }
  end
end
