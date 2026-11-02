# frozen_string_literal: true

require 'test_helper'

class GatewayTest < Minitest::Test
  T = BBS::Telnet

  def setup
    @session = FakeSession.new
    @board, @far = UNIXSocket.pair
  end

  def teardown
    [@board, @far].each { |io| io.close unless io.closed? }
    @session.fake_line.close
  end

  def run_link(bytes, **)
    link = BBS::Gateway::Link.new(@session, @board, terminal: 'ANSI', **)
    writer = Thread.new do
      @far.write(bytes)
      @far.close_write
    end
    hung_up = link.run
    writer.join
    hung_up
  end

  def test_data_crosses_and_a_255_stays_doubled
    refute run_link("hi\xFF\xFFho".b)
    assert_equal "hi\xFF\xFFho".b, @session.received
  end

  def test_a_long_subnegotiation_is_dropped_not_kept
    refute run_link("#{[T::IAC, T::SB, 24, 1].pack('C*')}#{'x' * 100_000}#{[T::IAC, T::SE].pack('C*')}hi")
    assert_equal 'hi', @session.received
  end

  def test_the_board_asking_for_the_terminal_type_and_window_size
    run_link([T::IAC, T::DO, T::NAWS_OPT, T::IAC, T::DO, 24, T::IAC, T::SB, 24, 1, T::IAC, T::SE].pack('C*'))
    answer = @far.read_nonblock(1000).bytes
    assert_equal [T::IAC, T::WILL, T::NAWS_OPT, T::IAC, T::SB, T::NAWS_OPT, 0, 80, 0, 24, T::IAC, T::SE],
                 answer.first(12)
    assert_equal [T::IAC, T::WILL, 24, T::IAC, T::SB, 24, 0, *'ANSI'.bytes, T::IAC, T::SE], answer.drop(12)
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

  def test_a_private_address_is_refused
    server = TCPServer.new('127.0.0.1', 0)
    report = nil
    _, log = capture_io do
      @session.fake_line.caller.write('x')
      BBS::Gateway.new(host: '127.0.0.1', port: server.addr[1]).call(@session) { |r| report = r }
    end
    refute report.connected
    assert_kind_of BBS::Gateway::Refused, report.error
    assert_match(/not a public address/, log)
    assert_match(/may not be called/, @session.received)
  ensure
    server&.close
  end

  def test_a_trusted_neighbour_is_called
    server = TCPServer.new('127.0.0.1', 0)
    caller = @session.fake_line.caller
    Thread.new do
      server.accept.tap { |c| c.write('welcome') }.close
      sleep 0.3
      caller.write('x')
    end
    report = nil
    BBS::Gateway.new(host: 'localhost', port: server.addr[1], public_only: false).call(@session) { |r| report = r }
    assert report.connected
    assert_equal '127.0.0.1', report.address.sub('::1', '127.0.0.1')
    assert_equal :board, report.hung_up
    assert_includes @session.received, 'welcome'
  ensure
    server&.close
  end
end
