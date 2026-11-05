# frozen_string_literal: true

# The board itself, whatever terminal a caller has: its settings
# (SAMPLE_BBS_*), its databases and its services, the guestbook and the
# accounts (Rubbs::Common::Auth: this board keeps its own, in a database of their own).
class SampleBBS
  include Rubbs::Common::Board::Domain

  path     :db, 'data/sample.sqlite3'
  path     :accounts_db, 'data/accounts.sqlite3'
  setting  :max_length, 200
  database :db, MIGRATIONS
  database :accounts_db, Rubbs::Common::Auth::MIGRATIONS, name: :auth

  service(:guestbook) { GuestbookService.new(max_length: max_length) }
  service(:directory) { Rubbs::Common::Auth::Directory.new(store: databases[:auth], roles: ['member']) }
end
