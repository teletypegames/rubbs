# frozen_string_literal: true

require 'test_helper'

class StoreTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def store(headers = %w[session_id timestamp name]) = BBS::Store.new(path: File.join(@dir, 'callers.csv'), headers: headers)

  def test_crud
    s = store
    s.upsert(session_id: 'a', name: "Ada\e[2J", junk: 'x')
    s.upsert(session_id: 'b', name: 'Bob')
    s.upsert(session_id: 'a', name: 'Ada L')
    assert_equal 'Ada L', s.find('a')['name']
    assert_match(/\A\d{4}-\d\d-\d\dT/, s.find('a')['timestamp'])
    assert_equal(%w[a b], s.all.map { |r| r['session_id'] })
    s.delete('a')
    assert_nil s.find('a')
    assert_equal 1, s.all.size
  end

  def test_values_are_cleaned
    s = store
    s.upsert(session_id: 'a', name: "x\u202Ey\u0085z\xFF".b)
    assert_equal 'xyz', s.find('a')['name']
  end

  def test_nothing_is_touched_before_use
    store
    assert_empty Dir.children(@dir)
  end

  def test_imports_a_csv_once
    File.write(File.join(@dir, 'callers.csv'), "session_id,timestamp,name\na,2020-01-01T00:00:00Z,Ada\nb,,Bo\xFFb\n".b)
    s = store
    capture_io { s.open! }
    assert_equal([%w[a Ada], %w[b Bob]], s.all.map { |r| [r['session_id'], r['name']] })
    assert_equal '2020-01-01T00:00:00Z', s.find('a')['timestamp']
    assert File.exist?(File.join(@dir, 'callers.csv.imported'))
    refute File.exist?(File.join(@dir, 'callers.csv'))
    assert File.exist?(File.join(@dir, 'callers.sqlite3'))
  end

  def test_broken_rows_are_set_aside
    csv = "session_id,timestamp,name\na,,Ada\nc,,\"two\nlines\"\n,,nokey\nd,,1,2,3,4\nb,\"unclosed,x\ne,,Eve\n"
    File.write(File.join(@dir, 'callers.csv'), csv)
    s = nil
    _, log = capture_io { s = store.open! }
    assert_equal(%w[a c e], s.all.map { |r| r['session_id'] })
    assert_equal "two\nlines", s.find('c')['name']
    rejected = File.read(File.join(@dir, 'callers.csv.rejected'))
    assert_equal "session_id,timestamp,name\n,,nokey\nd,,1,2,3,4\nb,\"unclosed,x\n", rejected
    assert_match(/3 rows .* 3 set aside/, log)
  end

  def test_open_imports_at_once
    File.write(File.join(@dir, 'callers.csv'), "session_id,timestamp,name\na,,Ada\n")
    capture_io { store.open! }
    assert File.exist?(File.join(@dir, 'callers.csv.imported'))
  end

  def test_new_columns_are_added
    store.upsert(session_id: 'a', name: 'Ada')
    s = store(%w[session_id timestamp name email])
    s.upsert(session_id: 'a', email: 'ada@example.org')
    assert_equal({ 'session_id' => 'a', 'timestamp' => s.find('a')['timestamp'], 'name' => 'Ada',
                   'email' => 'ada@example.org' }, s.find('a'))
  end

  def test_concurrent_upserts_keep_one_row_per_session
    s = store
    8.times.map { |i| Thread.new { 20.times { |j| s.upsert(session_id: "s#{j % 5}", name: "#{i}-#{j}") } } }.each(&:join)
    assert_equal 5, s.all.size
  end
end
