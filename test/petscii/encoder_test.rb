# frozen_string_literal: true

require 'test_helper'

class EncoderTest < Minitest::Test
  def bytes(text) = Rubbs::Petscii::Encoder.new.encode(text).bytes

  def test_letters_swap_case_for_the_lowercase_set
    assert_equal [0xd0, 0x49, 0x58], bytes('Pix')
  end

  def test_an_ascii_look_alike_swaps_case_like_a_letter
    assert_equal bytes('40x25'), bytes('40×25')
    assert_equal bytes('ss'), bytes('ß')
    assert_equal bytes('o'), bytes('°')
  end
end
