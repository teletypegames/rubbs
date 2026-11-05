# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

class DatabaseTest < Minitest::Test
  def setup
    @dir  = Dir.mktmpdir
    @path = File.join(@dir, 'deep', 'board.sqlite3')
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_migrations_run_once_in_order_by_user_version
    db = Rubbs::Common::Storage::Database.open(@path)
    assert_equal 0, Rubbs::Common::Storage::Database.version(db)
    steps = ['CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)', 'ALTER TABLE posts ADD COLUMN body TEXT',
             ->(d) { d[:posts].insert(title: 'seed') }]
    assert_equal 3, Rubbs::Common::Storage::Database.migrate(db, steps)
    assert_equal 3, Rubbs::Common::Storage::Database.migrate(db, %w[x y z])
    assert_equal [{ id: 1, title: 'seed', body: nil }], db[:posts].all
  end

  def test_a_database_of_bbs_sqlite_goes_on_where_it_was
    db = Rubbs::Common::Storage::Database.open(@path, ['CREATE TABLE t (a)'])
    db.run('PRAGMA user_version = 1')
    assert_equal 2, Rubbs::Common::Storage::Database.migrate(db, ['CREATE TABLE t (a)', 'CREATE TABLE u (a); CREATE TABLE v (a)'])
    assert_equal %i[t u v], db.tables.sort
  end

  def test_a_failing_migration_is_rolled_back
    db = Rubbs::Common::Storage::Database.open(@path, ['CREATE TABLE t (a)'])
    assert_raises(Sequel::DatabaseError) { Rubbs::Common::Storage::Database.migrate(db, ['CREATE TABLE t (a)', 'CREATE TABLE u (a); bogus']) }
    assert_equal 1, Rubbs::Common::Storage::Database.version(db)
    refute db.table_exists?(:u)
  end

  def test_wal_and_foreign_keys
    db = Rubbs::Common::Storage::Database.open(@path)
    assert_equal 'wal', db.fetch('PRAGMA journal_mode').single_value
    assert_equal 1, db.fetch('PRAGMA foreign_keys').single_value
  end
end

class ModelTest < Minitest::Test
  class NoteModel < Rubbs::Common::Storage::Model
    table :notes

    def self.by(author) = where(author: author)
    def shout = text.upcase
  end

  MIGRATIONS = ['CREATE TABLE notes (id INTEGER PRIMARY KEY, author TEXT NOT NULL, text TEXT NOT NULL)'].freeze

  def setup = Rubbs::Test.database(MIGRATIONS)

  def test_a_model_queries_and_writes_its_table
    NoteModel.create(author: 'ada', text: 'hello')
    NoteModel.create(author: 'bob', text: 'hi')
    assert_equal 2, NoteModel.count
    assert_equal ['HELLO'], NoteModel.by('ada').all.map(&:shout)
    counts = NoteModel.group_and_count(:author).order(:author).map { |r| [r[:author], r[:count].to_s] }
    assert_equal [%w[ada 1], %w[bob 1]], counts
    NoteModel.first(author: 'bob').update(text: 'bye')
    assert_equal 'bye', NoteModel.where(author: 'bob').get(:text)
  end

  def test_a_model_without_its_database_says_so
    loose = Class.new(Rubbs::Common::Storage::Model)
    error = assert_raises(Sequel::DatabaseError) { loose.count }
    assert_kind_of Rubbs::Common::Storage::Model::Unbound, error.wrapped_exception
    assert_raises(Sequel::DatabaseError) { loose.dataset.insert(text: 'y') }
  end

  def test_threads_write_through_the_pool
    4.times.map { |i| Thread.new { 10.times { NoteModel.create(author: "t#{i}", text: 'x') } } }.each(&:join)
    assert_equal 40, NoteModel.count
  end

  class Shop
    include Rubbs::Common::Board::Domain

    path     :db, 'shop.sqlite3'
    database :db, ModelTest::MIGRATIONS
    service(:notes) { NoteModel }
  end

  def test_a_domain_opens_its_database_and_binds_the_models
    Dir.mktmpdir do |dir|
      ENV['MODEL_TEST_SHOP_DB'] = File.join(dir, 'shop.sqlite3')
      Shop.env_prefix 'MODEL_TEST_SHOP_'
      prefix = Rubbs.config.env_prefix
      Rubbs.config.env_prefix = nil
      Shop.new.start
      NoteModel.create(author: 'ada', text: 'x')
      assert File.exist?(File.join(dir, 'shop.sqlite3'))
      assert_equal 1, NoteModel.count
    ensure
      Rubbs.config.env_prefix = prefix
      ENV.delete('MODEL_TEST_SHOP_DB')
    end
  end

  def test_a_domain_reports_its_health_and_stops
    Dir.mktmpdir do |dir|
      ENV['MODEL_TEST_SHOP_DB'] = File.join(dir, 'shop.sqlite3')
      Shop.env_prefix 'MODEL_TEST_SHOP_'
      shop = Shop.new.start
      assert_empty shop.health
      shop.stop
      assert_equal 0, shop.databases[:main].pool.size
    ensure
      ENV.delete('MODEL_TEST_SHOP_DB')
    end
  end
end
