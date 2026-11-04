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

  def with_login
    saved = BBS.config.auth
    BBS.config.auth = BBS::Auth::Setup.new(directory: Object.new, login: :menu, guests: true)
    yield
  ensure
    BBS.config.auth = saved
  end

  def test_a_board_with_a_login_asks_login_register_or_guest
    with_login do
      assert show(:modern, keys: 'xg')
      out = @session.received.force_encoding('UTF-8')
      green = BBS::Ansi::BRIGHT_GREEN
      assert_includes out, "#{green}L#{BBS::Ansi::WHITE}ogin#{BBS::Ansi::WHITE} | #{green}R#{BBS::Ansi::WHITE}egister"
      refute_includes out, BBS::Splash::PROMPT
    end
  end

  def test_login_and_register_open_the_profile_there
    started = []
    with_login do
      BBS::Auth::Profile.stub(:run, ->(_session, start:) { started << start }) do
        assert show(:modern, keys: 'l')
        assert show(:modern, keys: 'R')
      end
    end
    assert_equal %i[log_in register], started
  end

  def test_no_choices_without_a_login_or_for_one_logged_in
    assert show(:modern)
    assert_includes @session.received, BBS::Splash::PROMPT
    with_login do
      assert show(:modern, choices: nil)
      assert_includes @session.received, BBS::Splash::PROMPT
    end
  end

  def test_a_c64_gets_the_choices_in_capitals
    @session.petscii!
    @session.received
    with_login { assert show(:petscii, keys: 'g') }
    out = @session.received.delete_suffix(BBS::Petscii.bytes("#{BBS::Petscii::LOWERCASE}#{BBS::Petscii::CLEAR}"))
    row = BBS::Petscii::Canvas.new.feed(out).to_s.lines[BBS::Petscii::ROWS - 1]
    assert_includes row, 'LOGIN │ REGISTER │ GUEST'
  end
end
