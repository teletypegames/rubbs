# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GoodbyeTest < Minitest::Test
  QR_URL = 'HTTPS://EXAMPLE.ORG'

  def setup = BBS.config.preset = BBS::Preset.new(url: 'example.org', qr: QR_URL)

  def teardown = BBS.config.preset = BBS::Preset::NONE

  class Screen
    attr_reader :lines

    def initialize = @lines = []
    def cls = nil
    def cols = 40
    def puts(text = '') = @lines << text.to_s
    def say(text, color: nil) = @lines << "#{color} #{text}"
  end

  def test_modern_shows_the_qr_code_of_teletypegames
    text = BBS::Goodbye.modern_text(title: 'Feedia BBS')
    assert_equal BBS::QR.ansi(QR_URL, height: 15).size, text.scan(BBS::QR::PEN).size
    assert_operator text.index('More of us'), :<, text.index(BBS::QR::PEN)
    assert_operator text.index(BBS::QR::PEN), :<, text.index('NO CARRIER')
  end

  def test_modern_without_a_qr_code
    refute_includes BBS::Goodbye.modern_text(title: 'X', qr: nil), BBS::QR::PEN
    refute_includes BBS::Goodbye.modern_text(title: 'X', qr: 'x' * 500), BBS::QR::PEN
  end

  def test_the_smallest_code
    assert_equal 21, BBS::QR.modules(QR_URL).size
  end

  def test_without_a_preset_there_is_no_address_and_no_code
    BBS.config.preset = BBS::Preset::NONE
    text = BBS::Goodbye.modern_text(title: 'X', note: 'A note.')
    refute_includes text, 'More of us'
    refute_includes text, BBS::QR::PEN
    assert_includes text, 'A note.'
  end

  def test_petscii_centres_the_qr_code_before_hanging_up
    screen = Screen.new
    BBS::Goodbye.stub(:sleep, nil) { BBS::Goodbye.petscii(screen, title: 'feedia bbs') }
    code = screen.lines.select { |l| l.include?(BBS::QR::PEN) }
    assert_equal 13, code.size
    assert(code.all? { |l| l.start_with?("#{' ' * 13}#{BBS::QR::PEN}") })
    assert_operator(screen.lines.index(code.last), :<, screen.lines.index { |l| l.include?('NO CARRIER') })
  end

  def test_petscii_without_a_qr_code
    screen = Screen.new
    BBS::Goodbye.stub(:sleep, nil) { BBS::Goodbye.petscii(screen, title: 'x', qr: nil) }
    refute(screen.lines.any? { |l| l.include?(BBS::QR::PEN) })
  end
end
