# frozen_string_literal: true

require 'test_helper'

class CacheTest < Minitest::Test
  def test_ttl
    cache = BBS::Cache.new(ttl: 0.05, max_entries: 10)
    assert_equal 1, cache.fetch(:a) { 1 }
    assert_equal 1, cache.fetch(:a) { 2 }
    sleep 0.06
    assert_equal 3, cache.fetch(:a) { 3 }
  end

  def test_lru
    cache = BBS::Cache.new(ttl: 60, max_entries: 2)
    cache.fetch(:a) { 'a' }
    cache.fetch(:b) { 'b' }
    cache.fetch(:a) { 'x' }
    cache.fetch(:c) { 'c' }
    assert_equal 'a', cache.fetch(:a) { 'new' }
    assert_equal 'new b', cache.fetch(:b) { 'new b' }
    assert_equal 2, cache.size
  end

  def test_byte_cap
    cache = BBS::Cache.new(ttl: 60, max_entries: 10, max_bytes: 10)
    cache.fetch(:a) { 'aaaa' }
    cache.fetch(:b) { 'bbbb' }
    cache.fetch(:c) { 'cccc' }
    assert_equal 2, cache.size
    assert_equal 'again', cache.fetch(:a) { 'again' }
    cache.fetch(:huge) { 'x' * 11 }
    assert_equal 'kept?', cache.fetch(:huge) { 'kept?' }
  end

  def test_size_lambda
    cache = BBS::Cache.new(ttl: 60, max_entries: 10, max_bytes: 5, size: :size.to_proc)
    cache.fetch(:a) { [1, 2, 3] }
    cache.fetch(:b) { [1, 2, 3] }
    assert_equal 1, cache.size
  end

  def test_single_flight
    cache = BBS::Cache.new(ttl: 60, max_entries: 10)
    runs  = 0
    values = 8.times.map do
      Thread.new do
        cache.fetch(:k) do
          runs += 1
          sleep 0.1
          'v'
        end
      end
    end.map(&:value)
    assert_equal ['v'] * 8, values
    assert_equal 1, runs
  end

  def test_single_flight_shares_the_error
    cache = BBS::Cache.new(ttl: 60, max_entries: 10)
    results = 4.times.map do
      Thread.new do
        cache.fetch(:k) do
          sleep 0.05
          raise 'down'
        end
      rescue RuntimeError => e
        e.message
      end
    end.map(&:value)
    assert_equal ['down'] * 4, results
  end

  def test_stale_on_error
    cache = BBS::Cache.new(ttl: 0.01, max_entries: 10)
    cache.fetch(:a) { 'old' }
    sleep 0.02
    assert_equal 'old', cache.fetch(:a) { raise 'down' }
    assert_raises(RuntimeError) { cache.fetch(:b) { raise 'down' } }
  end

  def test_delete_and_clear
    cache = BBS::Cache.new(ttl: 60, max_entries: 10)
    cache.fetch(:a) { 1 }
    cache.fetch(:b) { 2 }
    cache.delete(:a)
    assert_equal 9, cache.fetch(:a) { 9 }
    cache.clear
    assert_equal 0, cache.size
  end
end
