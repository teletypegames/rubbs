# frozen_string_literal: true

require 'test_helper'
require 'socket'

# The server drained on a real port: the next process listens beside it.
class DrainTest < Minitest::Test
  def setup
    @saved = Rubbs.config
    Rubbs.config = c = @saved.dup
    c.shutdown_seconds = 0.5
    c.drain_seconds    = 5
    c.log_format       = :text
    c.flow = Rubbs::Common::Call::Flow.define { call { session.readkey && session.write('still here') && nil } }
    @drained = Queue.new
    c.on_drain = -> { @drained << true }
    @server = Rubbs::Common::Line::Server.new(port: 0)
  end

  def teardown
    @runner&.kill
    Rubbs.config = @saved
  end

  def test_two_listeners_share_a_port
    first  = Rubbs::Common::Line::Listener.tcp('127.0.0.1', 0)
    second = Rubbs::Common::Line::Listener.tcp('127.0.0.1', first.addr[1])
    assert_equal first.addr[1], second.addr[1]
  ensure
    first&.close
    second&.close
  end

  def test_a_drained_server_keeps_its_caller_and_takes_no_new_one
    serve
    socket = TCPSocket.new('127.0.0.1', @server.port)
    wait_until { @server.callers == 1 }
    _, err = capture_io do
      @runner.raise(Rubbs::Common::Line::Server::Drain)
      assert @drained.pop(timeout: 2)
      assert_raises(Errno::ECONNREFUSED) { TCPSocket.new('127.0.0.1', @server.port) }
      assert @runner.alive?
      assert_predicate @server, :draining?
      socket.write('x')
      @runner.join(5)
    end
    heard = socket.read
    assert_includes heard, 'The board has been updated.'
    assert_includes heard, 'still here'
    assert_match(/server: draining callers=1 wait=5/, err)
    assert_match(/server: stopped$/, err)
  ensure
    socket&.close
  end

  def test_drain_seconds_over_stop_the_server
    Rubbs.config.drain_seconds = 0.3
    serve
    socket = TCPSocket.new('127.0.0.1', @server.port)
    wait_until { @server.callers == 1 }
    capture_io do
      @runner.raise(Rubbs::Common::Line::Server::Drain)
      @runner.join(5)
    end
    refute @runner.alive?
    assert_includes socket.read, 'The board is restarting'
  ensure
    socket&.close
  end

  def test_without_drain_seconds_a_drain_is_a_stop
    Rubbs.config.drain_seconds = 0
    serve
    capture_io do
      @runner.raise(Rubbs::Common::Line::Server::Drain)
      @runner.join(5)
    end
    refute @runner.alive?
    assert_empty @drained
  end

  def test_a_board_drains_its_hooks_and_its_background_work
    domain = Class.new do
      include Rubbs::Common::Board::Domain

      background('tick', every: 60) { nil }
    end
    seen = []
    definition = Rubbs::Common::Board::BoardDefinition.new('Drain BBS', domain) do
      modern(Rubbs::Common::Call::Flow.define { text 'hi' })
      goodbye false
      on_drain { |board| seen << board }
    end
    capture_io { definition.configure }
    assert_equal 1, definition.board.send(:jobs).size
    capture_io { Rubbs.config.on_drain.call }
    assert_equal [definition.board], seen
    assert_empty definition.board.send(:jobs)
  ensure
    capture_io { definition&.stop }
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
