# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'bbs'
require 'bbs/test'
require 'domain'

# A guestbook in a throwaway database.
module TmpGuestbook
  def setup
    @dir       = Dir.mktmpdir
    @guestbook = GuestbookService.new(EntryRepository.new(BBS::SQLite.new(File.join(@dir, 'test.sqlite3')).tap do |db|
      db.migrate(*EntryRepository::MIGRATIONS)
    end), max_length: 20)
  end

  def teardown = FileUtils.remove_entry(@dir)
end
