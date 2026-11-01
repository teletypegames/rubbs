# frozen_string_literal: true

require 'test_helper'

class RateLimitTest < Minitest::Test
  def test_allow_and_wait
    limit = BBS::RateLimit.new(limit: 2, per: 0.2)
    assert limit.allow?(:a)
    assert limit.allow?(:a)
    refute limit.allow?(:a)
    assert limit.allow?(:b)
    assert_in_delta 0.2, limit.wait(:a), 0.05
    assert_equal 0.0, limit.wait(:c)
    sleep 0.21
    assert limit.allow?(:a)
  end

  def test_thread_safe
    limit = BBS::RateLimit.new(limit: 50, per: 60)
    allowed = 10.times.map { Thread.new { 20.times.count { limit.allow?(:k) } } }.sum(&:value)
    assert_equal 50, allowed
  end

  def test_old_keys_are_pruned
    limit = BBS::RateLimit.new(limit: 1, per: 0.05)
    100.times { |i| limit.allow?(i) }
    sleep 0.06
    limit.allow?(:fresh)
    assert_equal 1, limit.instance_variable_get(:@events).size
  end

  def test_caller_key
    assert_equal '8.8.8.8', BBS::RateLimit.caller_key(PeerSession.from('8.8.8.8'))
    assert_equal '8.8.4.4', BBS::RateLimit.caller_key(PeerSession.from('::ffff:8.8.4.4'))
    assert_equal 'line:abc', BBS::RateLimit.caller_key(PeerSession.from('172.18.0.5'))
    assert_equal 'line:abc', BBS::RateLimit.caller_key(PeerSession.from('127.0.0.1'))
    assert_equal 'line:abc', BBS::RateLimit.caller_key(PeerSession.new(nil, 'abc'))
  end
end
