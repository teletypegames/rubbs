# frozen_string_literal: true

# The schema of the guestbook, one step per version (BBS::Database.migrate).
MIGRATIONS = [
  'CREATE TABLE entries (id INTEGER PRIMARY KEY, name TEXT NOT NULL, text TEXT NOT NULL, written_at INTEGER NOT NULL)'
].freeze
