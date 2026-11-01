# frozen_string_literal: true

require 'test_helper'

class GatewayTest < Minitest::Test
  IAC = BBS::Telnet::IAC
  SB  = BBS::Telnet::SB
  SE  = BBS::Telnet::SE

  # Records the size of each subnegotiation the link parses.
  class RecordingLink < BBS::Gateway::Link
    attr_reader :subs

    private

    def subnegotiation(sub)
      (@subs ||= []) << sub.size
      super
    end
  end

  def setup
    @session = FakeSession.new
    @board, @far = UNIXSocket.pair
  end

  def teardown
    [@board, @far].each { |io| io.close unless io.closed? }
    @session.fake_line.close
  end

  def test_subnegotiation_is_capped
    link = RecordingLink.new(@session, @board, terminal: 'ANSI')
    writer = Thread.new do
      @far.write([IAC, SB, 24, 1].pack('C*'), 'x' * 100_000, [IAC, SE].pack('C*'), 'hi')
      @far.close_write
    end
    refute link.run
    writer.join
    assert_equal [BBS::Telnet::MAX_SUBNEGOTIATION], link.subs
    assert_equal 'hi', @session.received
  end

  def test_a_silent_line_ends_the_call
    link    = BBS::Gateway::Link.new(@session, @board, terminal: 'ANSI', idle: 0.2)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert link.run
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  def test_traffic_keeps_the_call
    link = BBS::Gateway::Link.new(@session, @board, terminal: 'ANSI', idle: 0.3)
    writer = Thread.new do
      5.times { @far.write('.') && sleep(0.1) }
      @far.close_write
    end
    refute link.run
    writer.join
    assert_equal '.....', @session.received
  end
end
