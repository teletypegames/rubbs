# frozen_string_literal: true

# The guestbook's lines in SQLite, newest first.
class EntryRepository
  MIGRATIONS = [
    'CREATE TABLE entries (id INTEGER PRIMARY KEY, name TEXT NOT NULL, text TEXT NOT NULL, written_at INTEGER NOT NULL)'
  ].freeze

  def initialize(db)
    @db = db
  end

  def all = @db.query('SELECT * FROM entries ORDER BY id DESC').map { |row| EntryModel.from_row(row) }

  def add(name, text, at: Time.now)
    @db.insert('INSERT INTO entries (name, text, written_at) VALUES (?, ?, ?)', name, text, at.to_i)
  end
end
