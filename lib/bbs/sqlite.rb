# frozen_string_literal: true

require 'fileutils'
require 'monitor'
require 'sqlite3'

module BBS
  # One SQLite file of a board and its one connection, shared by the
  # callers' threads behind a lock. The file is opened in WAL mode, so a
  # second process (a command-line tool of the board) can read and write it
  # meanwhile, with foreign keys on.
  #
  #   DB = BBS::SQLite.new('data/board.sqlite3')
  #   DB.migrate(
  #     'CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL)',
  #     'ALTER TABLE posts ADD COLUMN body TEXT'
  #   )
  #   id = DB.insert('INSERT INTO posts (title) VALUES (?)', 'Hello')
  #   DB.get('SELECT * FROM posts WHERE id = ?', id)   # => { 'id' => 1, 'title' => 'Hello', 'body' => nil }
  class SQLite
    # Milliseconds a statement waits for another process's lock.
    BUSY_TIMEOUT = 5000

    # The path of the database file.
    attr_reader :path

    # Opens (and creates, with its directory) the database file at +path+.
    # Raises SQLite3::Exception when it cannot.
    def initialize(path)
      @path = path.to_s
      FileUtils.mkdir_p(File.dirname(@path))
      @db = SQLite3::Database.new(@path, results_as_hash: true)
      @db.busy_timeout = BUSY_TIMEOUT
      @db.execute('PRAGMA journal_mode = WAL')
      @db.execute('PRAGMA foreign_keys = ON')
      @lock = Monitor.new
    end

    # Runs +sql+ with the bind values +args+ and returns its rows, an Array
    # of Hash (column name String => value).
    def query(sql, *args) = @lock.synchronize { @db.execute(sql, args) }

    # Returns the first row of #query, or +nil+.
    def get(sql, *) = query(sql, *).first

    # Runs the INSERT +sql+ and returns the rowid of the row it inserted.
    def insert(sql, *args) = run(sql, args) { @db.last_insert_row_id }

    # Runs +sql+ and returns the number of rows it changed.
    def change(sql, *args) = run(sql, args) { @db.changes }

    # Runs the block in one transaction, committed when it returns and
    # rolled back when it raises (the exception goes on). Inside another
    # transaction the block simply runs in that one. Returns the block's
    # value.
    def transaction(&)
      @lock.synchronize do
        return yield if @db.transaction_active?

        @db.transaction(:immediate, &)
      end
    end

    # The schema version of the file: <tt>PRAGMA user_version</tt>, 0 for a
    # new one.
    def version = get('PRAGMA user_version').values.first

    # Brings the schema up to date. +steps+ are the migrations in order,
    # each a String of SQL (one or more statements) or a callable given this
    # database; step N takes the file to version N. The steps a file has
    # had are skipped, the others run each in its own transaction. Returns
    # the version reached.
    def migrate(*steps)
      steps.each.with_index(1) do |step, number|
        next if number <= version

        transaction do
          step.respond_to?(:call) ? step.call(self) : @db.execute_batch(step)
          @db.execute("PRAGMA user_version = #{Integer(number)}")
        end
      end
      version
    end

    # Closes the connection.
    def close = @lock.synchronize { @db.close }

    private

    def run(sql, args)
      @lock.synchronize do
        @db.execute(sql, args)
        yield
      end
    end
  end
end
