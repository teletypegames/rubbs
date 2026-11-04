# frozen_string_literal: true

require 'test_helper'
require 'socket'

# The server on a real port: the health probe and the stop in order.
class StopTest < Minitest::Test
  def setup
    @saved = [BBS.config.flow, BBS.config.shutdown_seconds, BBS.config.on_session_end, BBS.config.health,
              BBS.config.log_format]
    BBS.config.shutdown_seconds = 0.5
    BBS.config.log_format = :text
    BBS.config.flow = BBS::Flow.define { call { readline } }
    @ended = Queue.new
    BBS.config.on_session_end = ->(session) { @ended << session.session_id }
    @server = BBS::Server.new(port: 0)
  end

  def teardown
    @runner&.kill
    BBS.config.flow, BBS.config.shutdown_seconds, BBS.config.on_session_end, BBS.config.health,
      BBS.config.log_format = @saved
  end

  def test_health_probe
    serve
    ok, line = BBS::Health.ask(port: @server.port)
    assert ok
    assert_match(%r{\AOK 0/\d+\z}, line)
  end

  def test_health_probe_reports_problems
    BBS.config.health = -> { ['database main: locked'] }
    serve
    assert_equal [false, 'FAIL database main: locked'], BBS::Health.ask(port: @server.port)
  end

  def test_a_caller_from_loopback_is_still_a_caller
    serve
    socket = TCPSocket.new('127.0.0.1', @server.port)
    assert socket.wait_readable(2)
    assert_equal "\r\n", socket.readpartial(2)
    wait_until { @server.callers == 1 }
  ensure
    socket&.close
  end

  def test_stop_tells_the_callers_and_hangs_up
    serve
    socket = TCPSocket.new('127.0.0.1', @server.port)
    wait_until { @server.callers == 1 }
    _, err = capture_io do
      @runner.raise(Interrupt)
      @runner.join(5)
    end
    heard = socket.read
    assert_includes heard, 'The board is restarting in 1 seconds.'
    refute_nil @ended.pop(timeout: 1)
    assert_match(/server: stopping callers=1/, err)
    assert_match(/call: ended .*end=stopped/, err)
    assert_match(/server: stopped$/, err)
    assert_raises(Errno::ECONNREFUSED) { TCPSocket.new('127.0.0.1', @server.port) }
  ensure
    socket&.close
  end

  def test_stop_without_callers_is_at_once
    serve
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    capture_io do
      @runner.raise(Interrupt)
      @runner.join(5)
    end
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.4
  end

  private

  def serve
    capture_io do
      @runner = Thread.new { @server.run }
      wait_until { @server.port.positive? }
    end
  end

  def wait_until(seconds = 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    assert yield
  end
end
