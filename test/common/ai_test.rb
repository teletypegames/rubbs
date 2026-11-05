# frozen_string_literal: true

require 'test_helper'

class AITest < Minitest::Test
  def test_semaphore_limits_and_times_out
    slots   = Rubbs::Common::AI::Semaphore.new
    holding = Queue.new
    release = Queue.new
    holder  = Thread.new { slots.hold(limit: 1, wait: 1) { (holding << 1) && release.pop } }
    holding.pop
    assert_raises(Rubbs::Common::AI::Busy) { slots.hold(limit: 1, wait: 0.1) { :never } }
    release << 1
    holder.join
    assert_equal :ran, slots.hold(limit: 1, wait: 0.1) { :ran }
  end

  def test_semaphore_waits_for_a_turn
    slots = Rubbs::Common::AI::Semaphore.new
    done  = 3.times.map { Thread.new { slots.hold(limit: 1, wait: 2) { sleep 0.05 } } }
    done.each(&:join)
  end

  def test_reply_cap
    server = TinyHTTP.new do |_path, client|
      line = %(data: {"choices":[{"delta":{"content":"#{'x' * 100}"}}]}\n)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n#{line * 50}")
    end
    client = Rubbs::Common::AI::Client.new(url: server.url('/'), max_bytes: 1000)
    taken  = +''
    assert_raises(Rubbs::Common::AI::Error) { client.stream([]) { |piece| taken << piece } }
    assert_operator taken.bytesize, :<=, 1000
  ensure
    server&.close
  end
end
