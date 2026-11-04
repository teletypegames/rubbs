# frozen_string_literal: true

require 'fileutils'
require 'sequel'

module BBS
  # A board's SQLite database through Sequel: opened in WAL mode with
  # foreign keys on and a busy timeout, its schema migrated by a list of
  # steps counted in <tt>PRAGMA user_version</tt> (the counter
  # BBS::SQLite#migrate used, so a database it made goes on where it was).
  #
  #   MIGRATIONS = [
  #     'CREATE TABLE entries (id INTEGER PRIMARY KEY, name TEXT NOT NULL, text TEXT NOT NULL)',
  #     'ALTER TABLE entries ADD COLUMN written_at INTEGER',
  #     ->(db) { db[:entries].update(written_at: Time.now.to_i) }
  #   ].freeze
  #
  #   db = BBS::Database.open('data/board.sqlite3', MIGRATIONS)
  #
  # A board does not call it: BBS::Domain's +database+ opens its databases
  # and BBS::Model binds the models to them.
  module Database
    # Milliseconds a write waits for another connection's lock.
    BUSY_TIMEOUT = 5000

    # The Sequel::Database at +path+ (made, with its folder, when missing),
    # migrated by +migrations+ (see ::migrate).
    #
    # [timeout]          milliseconds a write waits for a lock (BUSY_TIMEOUT)
    # [transaction_mode] how its transactions begin: +:immediate+ (the
    #                    default: a writer takes the lock at once, as
    #                    BBS::SQLite did) or +nil+ (deferred)
    def self.open(path, migrations = [], timeout: BUSY_TIMEOUT, transaction_mode: :immediate)
      FileUtils.mkdir_p(File.dirname(path.to_s))
      db = Sequel.sqlite(path.to_s, timeout: timeout,
                                    connect_sqls: ['PRAGMA journal_mode = WAL', 'PRAGMA foreign_keys = ON'])
      db.transaction_mode = transaction_mode if transaction_mode
      migrate(db, migrations)
      db
    end

    # The schema version of +db+ (<tt>PRAGMA user_version</tt>).
    def self.version(db) = db.fetch('PRAGMA user_version').single_value.to_i

    # Runs the steps of +migrations+ after the version of +db+, each in a
    # transaction with the version it brings: a String of SQL (one or more
    # statements) or a callable given the Sequel::Database. Returns the
    # version.
    def self.migrate(db, migrations)
      Array(migrations).each.with_index(1) do |step, number|
        next if number <= version(db)

        db.transaction do
          step.respond_to?(:call) ? step.call(db) : db.synchronize { |connection| connection.execute_batch(step) }
          db.run("PRAGMA user_version = #{Integer(number)}")
        end
      end
      version(db)
    end
  end
end
