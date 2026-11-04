# frozen_string_literal: true

# The board itself, whatever terminal a caller has: its settings
# (SAMPLE_BBS_*) and its one service, the guestbook.
class SampleBBS
  include BBS::Domain

  path    :db, 'data/sample.sqlite3'
  setting :max_length, 200

  service(:guestbook) do
    GuestbookService.new(EntryRepository.new(database(db, *EntryRepository::MIGRATIONS)), max_length: max_length)
  end
end
