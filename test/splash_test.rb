# frozen_string_literal: true

require 'test_helper'

class SplashTest < Minitest::Test
  MODERN = <<~YAML
    size: [4, 2]
    charset: cp437
    palette: { g: '#00ff00' }
    chars: |
      ▀▀▀▀
      ████
    colors: |
      gggg
      gggg
  YAML
  C64 = <<~YAML
    size: [2, 1]
    charset: petscii-upper
    palette: { g: green }
    chars: |
      ▄▄
    colors: |
      gg
  YAML

  def setup = @session = FakeSession.new

  def teardown = @session.fake_line.close

  def splash(**) = BBS::Splash.new(modern: BBS::Art.parse(MODERN), petscii: BBS::Art.parse(C64), **)

  def show(face, keys: 'x', **)
    @session.fake_line.caller.write(keys)
    Timeout.timeout(5) { splash(**).continue?(@session, face) }
  end

  def test_the_c64_drawing_must_be_petscii
    assert_raises(ArgumentError) { BBS::Splash.new(modern: BBS::Art.parse(MODERN), petscii: BBS::Art.parse(MODERN)) }
  end

  def test_modern_shows_the_drawing_centred_and_waits_for_a_key
    assert show(:modern)
    out = @session.received.force_encoding('UTF-8')
    assert_includes out, "#{' ' * 38}#{BBS::Art.parse(MODERN).ansi_lines.first}"
    assert_includes out, "#{' ' * 27}#{BBS::Ansi::GREY}#{BBS::Splash::PROMPT}"
  end

  def test_the_prompt_is_the_boards
    assert show(:modern, prompt: 'HIT IT')
    assert_includes @session.received, 'HIT IT'
  end

  def test_a_narrow_modern_terminal_gets_no_splash
    @session.instance_variable_set(:@term_cols, 3)
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
    refute Timeout.timeout(5) { splash.continue?(@session, :modern) }
  end
end
