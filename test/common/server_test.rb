# frozen_string_literal: true

require 'test_helper'

class ServerTest < Minitest::Test
  def setup
    @saved = [Rubbs.config.max_sessions, Rubbs.config.max_sessions_per_ip]
    Rubbs.config.max_sessions        = 10
    Rubbs.config.max_sessions_per_ip = 2
    @server = Rubbs::Common::Line::Server.new(port: 0)
  end

  def teardown
    Rubbs.config.max_sessions, Rubbs.config.max_sessions_per_ip = @saved
  end

  def test_per_ip_limit_for_public_peers
    assert_equal :ok, @server.admit('8.8.8.8')
    assert_equal :ok, @server.admit('8.8.8.8')
    assert_equal :crowded, @server.admit('8.8.8.8')
    assert_equal :ok, @server.admit('1.1.1.1')
    @server.release('8.8.8.8')
    assert_equal :ok, @server.admit('8.8.8.8')
  end

  def test_the_calls_on_the_line_and_hanging_one_up
    socket = Struct.new(:closed) { def close = self.closed = true }.new(false)
    sessions = 2.times.map { Rubbs::Common::Line::Session.new(socket) }
    threads = sessions.map { |s| Thread.new { @server.send(:enlist, s) } }.each(&:join)
    assert_equal sessions.sort_by(&:started_at), @server.live
    Rubbs::Common::Line::Server.current = @server
    assert_equal 2, Rubbs.calls.size
    sessions.first.hang_up
    assert socket.closed
  ensure
    Rubbs::Common::Line::Server.current = nil
    threads&.each(&:kill)
  end

  def test_local_peers_are_not_limited_per_ip
    5.times { assert_equal :ok, @server.admit('172.18.0.5') }
    3.times { assert_equal :ok, @server.admit(nil) }
  end

  def test_total_limit
    10.times { |i| assert_equal :ok, @server.admit("10.0.0.#{i}") }
    assert_equal :busy, @server.admit('8.8.8.8')
    @server.release('10.0.0.1')
    assert_equal :ok, @server.admit('8.8.8.8')
  end

  def test_default_per_ip_limit
    assert_equal 6, Rubbs::Common::Board::Config.new.max_sessions_per_ip
  end
end
