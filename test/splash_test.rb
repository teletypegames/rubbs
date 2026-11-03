# frozen_string_literal: true

require 'test_helper'

class SplashTest < Minitest::Test
  def setup = @session = FakeSession.new

  def teardown = @session.fake_line.close

  def show(face, keys: 'x')
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { BBS::Splash.continue?(@session, face) }
  end

  def test_both_drawings_load_from_the_same_pixels
    modern = BBS::Splash.art(:modern)
    c64    = BBS::Splash.art(:petscii)
    assert_equal [66, 23], [modern.cols, modern.rows]
    assert_equal [33, 23], [c64.cols, c64.rows]
    assert c64.petscii?
  end

  def test_modern_shows_the_logo_centred_and_waits_for_a_key
    assert show(:modern)
    out = @session.received.force_encoding('UTF-8')
    assert_includes out, "       #{BBS::Splash.art(:modern).ansi_lines.first}"
    assert_includes out, "#{' ' * 27}#{BBS::Ansi::GREY}#{BBS::Splash::PROMPT}"
  end

  def test_a_narrow_modern_terminal_gets_no_logo
    @session.instance_variable_set(:@term_cols, 60)
    assert show(:modern)
    assert_empty @session.received
  end

  def test_c64_gets_the_canvas_and_its_lowercase_set_back
    @session.petscii!
    @session.received
    assert show(:petscii)
    out = @session.received
    assert out.start_with?([BBS::Petscii::UPPERCASE.ord, BBS::Petscii::CLEAR.ord].pack('C*'))
    assert out.end_with?(BBS::Petscii.bytes("#{BBS::Petscii::LOWERCASE}#{BBS::Petscii::CLEAR}"))
  end

  def test_a_dropped_line_is_false
    @session.fake_line.caller.close
    refute Timeout.timeout(5) { BBS::Splash.continue?(@session, :modern) }
  end
end
