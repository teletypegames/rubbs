# frozen_string_literal: true

require 'test_helper'

class AsciiBridgeTest < Minitest::Test
  P = Rubbs::Petscii

  def bridge = @bridge ||= Rubbs::Common::Line::Gateway::AsciiBridge.new

  def test_letters_swap_case_for_the_c64
    assert_equal "\xC8ELLO".b, bridge.down('Hello')
  end

  def test_an_ansi_colour_becomes_a_c64_colour_code
    assert_includes bridge.down("\e[31mred"), P::RED
  end

  def test_cp437_line_drawing_is_decoded_not_dropped
    assert_equal Rubbs::Common::Line::Gateway::AsciiBridge.new.down('──x'), bridge.down("\xC4\xC4x".b)
  end

  def test_once_cp437_a_line_byte_at_the_end_is_not_held_back
    bridge.down("\xC4x".b)
    assert_equal Rubbs::Common::Line::Gateway::AsciiBridge.new.down('─'), bridge.down("\xC4".b)
  end

  def test_a_utf8_character_cut_in_two_waits_for_its_end
    first, second = '─'.b.then { |b| [b.byteslice(0, 2), b.byteslice(2..)] }
    assert_empty bridge.down(first)
    assert_equal Rubbs::Common::Line::Gateway::AsciiBridge.new.down('─'), bridge.down(second)
  end

  def test_a_byte_255_goes_down_doubled
    assert_predicate bridge.down('π').count("\xFF".b), :even?
  end

  def test_the_c64_keys_go_up_as_an_ansi_terminal_sends_them
    keys = [0x48, 0xC9, 0x0d, P::DEL.ord, P::UP.ord, 0x03, 0x85, 0x5c].pack('C*')
    assert_equal "hI\r\b\e[A\e#".b, bridge.up(keys)
  end

  def test_a_petscii_caller_is_an_ansi_terminal_of_its_size_behind_a_bridge
    session = FakeSession.new
    session.define_singleton_method(:petscii?) { true }
    board, far = UNIXSocket.pair
    link = Rubbs::Common::Line::Gateway::Link.new(session, board, terminal: 'XTERM-256COLOR', bridge: Rubbs::Common::Line::Gateway::AsciiBridge.new)
    negotiation = link.instance_variable_get(:@negotiation)
    assert_equal 'ANSI', negotiation.instance_variable_get(:@terminal)
    refute negotiation.instance_variable_get(:@petscii)
  ensure
    [board, far].each { |io| io&.close }
    session&.fake_line&.close
  end
end
