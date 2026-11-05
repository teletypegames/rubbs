# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GoodbyeTest < Minitest::Test
  QR_URL = 'HTTPS://EXAMPLE.ORG'

  def setup = Rubbs.config.preset = Rubbs::Common::Board::Preset.new(url: 'example.org', qr: QR_URL)

  def teardown = Rubbs.config.preset = Rubbs::Common::Board::Preset::NONE

  class Screen
    attr_reader :lines

    def initialize = @lines = []
    def cls = nil
    def cols = 40
    def puts(text = '') = @lines << text.to_s
    def say(text, color: nil) = @lines << "#{color} #{text}"
  end

  def test_modern_shows_the_qr_code_of_teletypegames
    text = Rubbs::Modern::Goodbye.text(title: 'Feedia BBS')
    assert_equal Rubbs::Common::Text::QR.ansi(QR_URL, height: 15).size, text.scan(Rubbs::Common::Text::QR::PEN).size
    assert_operator text.index('More of us'), :<, text.index(Rubbs::Common::Text::QR::PEN)
    assert_operator text.index(Rubbs::Common::Text::QR::PEN), :<, text.index('NO CARRIER')
  end

  def test_modern_without_a_qr_code
    refute_includes Rubbs::Modern::Goodbye.text(title: 'X', qr: nil), Rubbs::Common::Text::QR::PEN
    refute_includes Rubbs::Modern::Goodbye.text(title: 'X', qr: 'x' * 500), Rubbs::Common::Text::QR::PEN
  end

  def test_the_smallest_code
    assert_equal 21, Rubbs::Common::Text::QR.modules(QR_URL).size
  end

  def test_without_a_preset_there_is_no_address_and_no_code
    Rubbs.config.preset = Rubbs::Common::Board::Preset::NONE
    text = Rubbs::Modern::Goodbye.text(title: 'X', note: 'A note.')
    refute_includes text, 'More of us'
    refute_includes text, Rubbs::Common::Text::QR::PEN
    assert_includes text, 'A note.'
  end

  def test_petscii_centres_the_qr_code_before_hanging_up
    screen = Screen.new
    Rubbs::Petscii::Goodbye.stub(:sleep, nil) { Rubbs::Petscii::Goodbye.show(screen, title: 'feedia bbs') }
    code = screen.lines.select { |l| l.include?(Rubbs::Common::Text::QR::PEN) }
    assert_equal 13, code.size
    assert(code.all? { |l| l.start_with?("#{' ' * 13}#{Rubbs::Common::Text::QR::PEN}") })
    assert_operator(screen.lines.index(code.last), :<, screen.lines.index { |l| l.include?('NO CARRIER') })
  end

  def test_petscii_without_a_qr_code
    screen = Screen.new
    Rubbs::Petscii::Goodbye.stub(:sleep, nil) { Rubbs::Petscii::Goodbye.show(screen, title: 'x', qr: nil) }
    refute(screen.lines.any? { |l| l.include?(Rubbs::Common::Text::QR::PEN) })
  end
end
