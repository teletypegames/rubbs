# frozen_string_literal: true

require 'test_helper'

class SQLiteTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @db  = BBS::SQLite.new(File.join(@dir, 'deep', 'board.sqlite3'))
  end

  def teardown
    @db.close
    FileUtils.rm_rf(@dir)
  end

  def test_migrations_run_once_in_order
    assert_equal 0, @db.version
    assert_equal 1, @db.migrate('CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)')
    assert_equal 3, @db.migrate('CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)',
                                'ALTER TABLE posts ADD COLUMN body TEXT',
                                ->(db) { db.insert('INSERT INTO posts (title) VALUES (?)', 'seed') })
    assert_equal 3, @db.migrate('x', 'y', 'z')
    assert_equal [{ 'id' => 1, 'title' => 'seed', 'body' => nil }], @db.query('SELECT * FROM posts')
  end

  def test_a_failing_migration_is_rolled_back
    @db.migrate('CREATE TABLE t (a)')
    assert_raises(SQLite3::Exception) { @db.migrate('CREATE TABLE t (a)', 'CREATE TABLE u (a); bogus') }
    assert_equal 1, @db.version
    assert_empty @db.query("SELECT name FROM sqlite_master WHERE name = 'u'")
  end

  def test_insert_change_get_and_transaction
    @db.migrate('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)')
    id = @db.insert('INSERT INTO t (v) VALUES (?)', 'a')
    assert_equal({ 'id' => id, 'v' => 'a' }, @db.get('SELECT * FROM t WHERE id = ?', id))
    assert_equal 1, @db.change('UPDATE t SET v = ? WHERE id = ?', 'b', id)
    assert_raises(RuntimeError) do
      @db.transaction do
        @db.insert('INSERT INTO t (v) VALUES (?)', 'c')
        @db.transaction { @db.insert('INSERT INTO t (v) VALUES (?)', 'd') }
        raise 'undo'
      end
    end
    assert_equal(['b'], @db.query('SELECT v FROM t').map { |r| r['v'] })
    assert_nil @db.get('SELECT * FROM t WHERE id = ?', 99)
  end

  def test_wal_and_foreign_keys
    assert_equal 'wal', @db.get('PRAGMA journal_mode')['journal_mode']
    assert_equal 1, @db.get('PRAGMA foreign_keys')['foreign_keys']
  end
end
