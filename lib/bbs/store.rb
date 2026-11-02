# frozen_string_literal: true

require 'time'
require_relative 'store/csv_import'

module BBS
  # A small thread-safe table keyed by session id, for keeping what callers
  # entered, in a BBS::SQLite file. The file and the table are created on
  # first use; a column added to +headers+ later is added to the table.
  #
  #   store = BBS::Store.new(path: 'data/callers.csv', headers: %w[session_id timestamp name])
  #   store.upsert(session_id: ctx[:session_id], name: 'Ada')
  #
  # A +path+ ending in <tt>.csv</tt> names the CSV file of earlier versions:
  # the database is the <tt>.sqlite3</tt> file beside it, and on first use
  # (or at boot, with #open!) the rows of the CSV file (when it exists and
  # the table is empty) are imported in one transaction and the CSV file is
  # renamed to <tt><name>.csv.imported</tt>. A row that is not CSV, has more
  # fields than the header or no +session_id+ is skipped and set aside in
  # <tt><name>.csv.rejected</tt> (see Store::CsvImport).
  #
  # The +session_id+ column is the key; a +timestamp+ column, when present,
  # is filled with the UTC time a row is created.
  class Store
    # The table that holds the rows.
    TABLE = 'store'
    # The key column, kept even when +headers+ leave it out.
    KEY = 'session_id'

    # The column names (an Array of String) and the path the store was made
    # with (see the class description for the database file).
    attr_reader :headers, :path

    # Creates a store at +path+ with the column names +headers+. The file is
    # not touched until the first read or write.
    def initialize(path:, headers:)
      @path    = path.to_s
      @headers = headers.map(&:to_s)
      @mutex   = Mutex.new
    end

    # Opens the database now (creating the file and the table, importing a
    # CSV file) instead of on first use, so a board can do it at boot.
    # Returns +self+.
    def open!
      db
      self
    end

    # The path of the SQLite file: +path+, or the <tt>.sqlite3</tt> file
    # beside it when +path+ names a CSV file.
    def database_path = @path.sub(/\.csv\z/, '.sqlite3')

    # Updates the row of +session_id+ with +fields+, or adds a new row when
    # there is none. Keys that are not columns are ignored; values are
    # stored as strings cleaned with BBS::Text.clean.
    #
    # Returns +self+.
    def upsert(session_id:, **fields)
      values = fields.filter_map { |name, value| [name.to_s, clean(value)] if @headers.include?(name.to_s) }.to_h
      db.transaction { find(session_id) ? update(session_id, values) : add(session_id, fields) }
      self
    end

    # Returns the row of +session_id+ as a Hash of column name to value, or
    # +nil+.
    def find(session_id)
      row = db.get("SELECT * FROM #{TABLE} WHERE #{KEY} = ?", session_id.to_s)
      row && project(row)
    end

    # Returns every row as an Array of Hash, oldest first.
    def all = db.query("SELECT * FROM #{TABLE} ORDER BY rowid").map { |row| project(row) }

    # Removes the row of +session_id+, if there is one.
    def delete(session_id)
      db.change("DELETE FROM #{TABLE} WHERE #{KEY} = ?", session_id.to_s)
      nil
    end

    private

    def db = @mutex.synchronize { @db ||= open }

    def open
      SQLite.new(database_path).tap do |db|
        db.query("CREATE TABLE IF NOT EXISTS #{TABLE} (#{KEY} TEXT UNIQUE)")
        known = db.query("PRAGMA table_info(#{TABLE})").map { |column| column['name'] }
        (@headers - known).each { |name| db.query("ALTER TABLE #{TABLE} ADD COLUMN #{quote(name)} TEXT") }
        import(db) if @path != database_path && File.exist?(@path)
      end
    end

    def update(session_id, values)
      return if values.empty?

      sets = values.keys.map { |name| "#{quote(name)} = ?" }.join(', ')
      db.change("UPDATE #{TABLE} SET #{sets} WHERE #{KEY} = ?", *values.values, session_id.to_s)
    end

    def add(session_id, fields)
      row = @headers.to_h { |name| [name, fields[name.to_sym]&.then { |value| clean(value) }] }
      row['timestamp'] = Time.now.utc.iso8601 if @headers.include?('timestamp')
      insert(db, row.merge(KEY => session_id.to_s))
    end

    def insert(db, row)
      names = row.keys.map { |name| quote(name) }.join(', ')
      db.insert("INSERT OR IGNORE INTO #{TABLE} (#{names}) VALUES (#{(['?'] * row.size).join(', ')})", *row.values)
    end

    def import(db)
      return unless db.get("SELECT COUNT(*) AS n FROM #{TABLE}")['n'].zero?

      csv = CsvImport.new(@path, [KEY, *@headers])
      db.transaction { csv.rows.each { |row| insert(db, row.transform_values { |value| value && clean(value) }) } }
      BBS.log('store', csv.finish(database_path))
    end

    def project(row) = @headers.to_h { |name| [name, row[name]] }

    def quote(name) = %("#{name.gsub('"', '""')}")

    def clean(value) = Text.clean(value)
  end
end
