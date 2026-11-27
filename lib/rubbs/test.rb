# frozen_string_literal: true

require 'rubbs'
require 'tmpdir'
require 'fileutils'

module Rubbs
  # Helpers for the tests of a board, loaded with <tt>require 'rubbs/test'</tt>
  # (not by <tt>require 'rubbs'</tt>).
  module Test
    # A throwaway database for a test: a fresh SQLite file migrated by
    # +migrations+, the Rubbs::Common::Storage::Model classes of +name+ bound to it. Returns the
    # Sequel::Database; the file goes when the process ends.
    #
    #   def setup = Rubbs::Test.database(MIGRATIONS)
    def self.database(migrations = [], name: :main)
      dir = Dir.mktmpdir('bbs-test')
      at_exit { FileUtils.rm_rf(dir) }
      db = Common::Storage::Database.open(File.join(dir, 'test.sqlite3'), migrations)
      Common::Storage::Model.bind(name => db)
      db
    end

    # The secret the test's tokens are signed with (Rubbs::Common::Auth::Token).
    SECRET = 'rubbs test secret, never a real one'

    # Sets +secret+ as the shared secret of Rubbs::Common::Auth (Rubbs.config.auth_secrets)
    # and forgets the tokens taken so far. Returns the secret.
    def self.auth_secret(secret = SECRET)
      Rubbs.config.auth_secrets = [secret]
      Common::Auth::Token.forget!
      secret
    end

    # A fresh accounts database (Rubbs::Common::Auth::MIGRATIONS, bound as +:auth+) and
    # a Rubbs::Common::Auth::Directory on it with +options+.
    #
    #   directory = Rubbs::Test.accounts(roles: ['member'])
    #   directory.register('ada', 'secret1')
    def self.accounts(**)
      Directory.new(store: database(Common::Auth::MIGRATIONS, name: :auth), **)
    end

    # The directory class of ::accounts.
    Directory = Common::Auth::Directory
  end
end

require_relative 'test/session'
require_relative 'test/helpers'
require_relative 'test/scripted_line'
require_relative 'test/case'
