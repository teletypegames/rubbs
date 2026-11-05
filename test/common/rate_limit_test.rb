# frozen_string_literal: true

require 'test_helper'

class RateLimitTest < Minitest::Test
  def test_allow_and_wait
    limit = Rubbs::Common::Line::RateLimit.new(limit: 2, per: 0.2)
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
    limit = Rubbs::Common::Line::RateLimit.new(limit: 50, per: 60)
    allowed = 10.times.map { Thread.new { 20.times.count { limit.allow?(:k) } } }.sum(&:value)
    assert_equal 50, allowed
  end

  def test_old_keys_are_pruned
    limit = Rubbs::Common::Line::RateLimit.new(limit: 1, per: 0.05)
    100.times { |i| limit.allow?(i) }
    sleep 0.06
    limit.allow?(:fresh)
    assert_equal 1, limit.instance_variable_get(:@events).instance_variable_get(:@times).size
  end

  def test_allow_all_counts_in_every_limit_or_in_none
    caller = Rubbs::Common::Line::RateLimit.new(limit: 2, per: 60)
    board  = Rubbs::Common::Line::RateLimit.new(limit: 3, per: 60)
    assert Rubbs::Common::Line::RateLimit.allow_all?([[caller, :ada], [board, :all]])
    assert Rubbs::Common::Line::RateLimit.allow_all?([[caller, :ada], [board, :all]])
    refute Rubbs::Common::Line::RateLimit.allow_all?([[caller, :ada], [board, :all]])
    assert board.room?(:all), 'the refused event was not counted on the board'
    assert Rubbs::Common::Line::RateLimit.allow_all?([[caller, :bob], [board, :all]])
    refute Rubbs::Common::Line::RateLimit.allow_all?([[caller, :cy], [board, :all]])
    assert caller.room?(:cy), 'the refused event was not counted for the caller'
  end

  def test_room_and_record_apart
    logins = Rubbs::Common::Line::RateLimit.new(limit: 2, per: 60)
    assert logins.room?(:k)
    3.times { logins.record(:k) }
    refute logins.room?(:k)
    assert_operator logins.wait(:k), :>, 59
  end

  def test_a_stored_limit_outlasts_a_restart
    Dir.mktmpdir do |dir|
      db = Rubbs::Common::Storage::Database.open(File.join(dir, 'limits.sqlite3'))
      2.times { Rubbs::Common::Line::RateLimit.new(limit: 2, per: 60, store: db, name: 'logins').record('1.2.3.4') }
      again = Rubbs::Common::Line::RateLimit.new(limit: 2, per: 60, store: db, name: 'logins')
      refute again.allow?('1.2.3.4')
      assert Rubbs::Common::Line::RateLimit.new(limit: 2, per: 60, store: db, name: 'tips').allow?('1.2.3.4')
      assert_operator again.wait('1.2.3.4'), :>, 59
    end
  end

  def test_stored_events_expire
    Dir.mktmpdir do |dir|
      store = Rubbs::Common::Storage::Database.open(File.join(dir, 'l.sqlite3'))
      limit = Rubbs::Common::Line::RateLimit.new(limit: 1, per: 0.05, store: store, name: 'x')
      assert limit.allow?(:k)
      refute limit.allow?(:k)
      sleep 0.06
      assert limit.allow?(:k)
    end
  end

  def test_a_stored_limit_needs_a_name
    assert_raises(ArgumentError) { Rubbs::Common::Line::RateLimit.new(limit: 1, per: 1, store: Object.new) }
  end

  def test_caller_key
    assert_equal '8.8.8.8', Rubbs::Common::Line::RateLimit.caller_key(PeerSession.from('8.8.8.8'))
    assert_equal '8.8.4.4', Rubbs::Common::Line::RateLimit.caller_key(PeerSession.from('::ffff:8.8.4.4'))
    assert_equal 'line:abc', Rubbs::Common::Line::RateLimit.caller_key(PeerSession.from('172.18.0.5'))
    assert_equal 'line:abc', Rubbs::Common::Line::RateLimit.caller_key(PeerSession.from('127.0.0.1'))
    assert_equal 'line:abc', Rubbs::Common::Line::RateLimit.caller_key(PeerSession.new(nil, 'abc'))
  end
end
