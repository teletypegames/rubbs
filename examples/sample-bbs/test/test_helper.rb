# frozen_string_literal: true

require 'minitest/autorun'
require 'rubbs'
require 'rubbs/test'
require 'domain'

# A guestbook in a throwaway database.
module TmpGuestbook
  def setup
    Rubbs::Test.database(MIGRATIONS)
    @guestbook = GuestbookService.new(max_length: 20)
  end
end
