# frozen_string_literal: true

require 'test_helper'

class TelnetParserTest < Minitest::Test
  T = BBS::Telnet

  def setup
    @commands = []
    @parser   = T::Parser.new { |command, argument| @commands << [command, argument] }
  end

  def test_data_passes_and_a_doubled_iac_is_one_byte
    assert_equal "a\xFFb".b, @parser.parse("a\xFF\xFFb".b)
    assert_empty @commands
  end

  def test_option_commands_go_to_the_block
    assert_equal 'xy', @parser.parse([120, T::IAC, T::WILL, T::ECHO_OPT, 121].pack('C*'))
    assert_equal [[T::WILL, T::ECHO_OPT]], @commands
  end

  def test_a_subnegotiation_with_a_doubled_iac
    @parser.parse([T::IAC, T::SB, T::NAWS_OPT, 0, T::IAC, T::IAC, 0, 24, T::IAC, T::SE].pack('C*'))
    assert_equal [[T::SB, [T::NAWS_OPT, 0, 255, 0, 24]]], @commands
  end

  def test_a_subnegotiation_is_capped
    @parser.parse([T::IAC, T::SB].pack('C*') + ('x' * 1000) + [T::IAC, T::SE].pack('C*'))
    assert_equal T::MAX_SUBNEGOTIATION, @commands.first.last.size
  end

  def test_a_command_split_over_two_reads
    assert_equal '', @parser.parse([T::IAC].pack('C*'))
    assert_equal 'z', @parser.parse([T::DO, T::SGA_OPT, 122].pack('C*'))
    assert_equal [[T::DO, T::SGA_OPT]], @commands
  end

  def test_other_commands_are_dropped
    assert_equal 'ok', @parser.parse([T::IAC, 241, 111, 107].pack('C*'))
    assert_empty @commands
  end
end
