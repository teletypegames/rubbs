# frozen_string_literal: true

# The board itself, whatever terminal a caller has: its settings
# (SAMPLE_BBS_*), its database and its one service, the guestbook.
class SampleBBS
  include BBS::Domain

  path     :db, 'data/sample.sqlite3'
  setting  :max_length, 200
  database :db, MIGRATIONS

  service(:guestbook) { GuestbookService.new(max_length: max_length) }
end
