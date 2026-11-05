# frozen_string_literal: true

require 'bbs'
require 'tmpdir'
require 'fileutils'

module BBS
  # Helpers for the tests of a board, loaded with <tt>require 'bbs/test'</tt>
  # (not by <tt>require 'bbs'</tt>).
  module Test
    # A throwaway database for a test: a fresh SQLite file migrated by
    # +migrations+, the BBS::Model classes of +name+ bound to it. Returns the
    # Sequel::Database; the file goes when the process ends.
    #
    #   def setup = BBS::Test.database(MIGRATIONS)
    def self.database(migrations = [], name: :main)
      dir = Dir.mktmpdir('bbs-test')
      at_exit { FileUtils.rm_rf(dir) }
      db = Database.open(File.join(dir, 'test.sqlite3'), migrations)
      Model.bind(name => db)
      db
    end

    # The secret the test's tokens are signed with (BBS::Auth::Token).
    SECRET = 'rubbs test secret, never a real one'

    # Sets +secret+ as the shared secret of BBS::Auth (BBS.config.auth_secrets)
    # and forgets the tokens taken so far. Returns the secret.
    def self.auth_secret(secret = SECRET)
      BBS.config.auth_secrets = [secret]
      Auth::Token.forget!
      secret
    end

    # A fresh accounts database (BBS::Auth::MIGRATIONS, bound as +:auth+) and
    # a BBS::Auth::Directory on it with +options+.
    #
    #   directory = BBS::Test.accounts(roles: ['member'])
    #   directory.register('ada', 'secret1')
    def self.accounts(**)
      Directory.new(store: database(Auth::MIGRATIONS, name: :auth), **)
    end

    # The directory class of ::accounts.
    Directory = Auth::Directory

    # A caller's line without a socket: the keys it will press go in, what
    # the board writes is kept. It answers what a page, a screen or a flow
    # asks of a BBS::Session.
    #
    #   session = BBS::Test::Session.new(keys: [:down, :enter, 'q'])
    #   BBS::Pages.new(session).run(Home.new)
    #   assert_includes session.output, 'Global Discovery'
    #
    #   c64 = BBS::Test::Session.new(petscii: true)
    #   c64.keys << ' '           # a key for later
    #   c64.take                  # the bytes written since the last take
    class Session
      # The keys still to come, first first: Strings and Symbols as
      # BBS::Telnet#readkey returns them (+:idle+ too). Push more any time.
      attr_reader :keys
      # Every write and raw write so far, each a binary String, in order.
      attr_reader :writes
      # The terminal's width and height (40×25 on a PETSCII line).
      attr_accessor :term_cols, :term_rows
      # The idle limit in seconds, +nil+ for none (see BBS::Session).
      attr_accessor :idle_seconds
      # The session id, 'test' unless given.
      attr_reader :session_id
      # Who the caller is (a BBS::Auth::Identity); a guest unless given,
      # changed by a login or a logout.
      attr_accessor :identity
      # The face the call got (+:modern+ or +:petscii+, see
      # BBS::Session#face), +nil+ until one is set.
      attr_accessor :face
      # The variables a neighbouring board forwarded (see
      # BBS::Telnet::Forwarded#forwarded), a Hash; empty unless given.
      attr_reader :forwarded

      # A line with +keys+ to press.
      #
      # [petscii] whether the line is a C64 in PETSCII mode
      # [cols]    the terminal width (ignored on a PETSCII line)
      # [rows]    the terminal height (ignored on a PETSCII line)
      # [identity]  who the caller is (a BBS::Auth::Identity)
      # [forwarded] the forwarded variables (BBS_VIA, RUBBS_AUTH_KEY …)
      def initialize(keys: [], petscii: false, cols: 80, rows: 24, session_id: 'test', identity: nil, forwarded: {})
        @keys       = keys.dup
        @petscii    = petscii
        @term_cols  = petscii ? Petscii::COLS : cols
        @term_rows  = petscii ? Petscii::ROWS : rows
        @session_id = session_id
        @writes     = []
        @taken      = 0
        @idle_seconds = nil
        @forwarded    = forwarded
        @identity     = identity || Auth::Identity.guest
      end

      # The board the call came through (BBS_VIA), or +nil+.
      def via = @forwarded['BBS_VIA']

      # The caller's address (BBS_CLIENT_IP), or +nil+.
      def caller_ip = @forwarded['BBS_CLIENT_IP']

      # Whether the line is in PETSCII mode.
      def petscii? = @petscii

      # Switches the line to PETSCII mode, 40×25.
      def petscii!
        @petscii   = true
        @term_cols = Petscii::COLS
        @term_rows = Petscii::ROWS
      end

      # Keeps +text+ as written. Returns +nil+.
      def write(text)
        @writes << text.to_s.b
        nil
      end

      # Keeps +bytes+ as written raw. Returns +nil+.
      def write_raw(bytes) = write(bytes)

      # The next key of #keys; +nil+ (the caller hung up) when there is
      # none left. A +timeout:+ is taken and ignored. A callable among the
      # keys is called with the session when its turn comes (something
      # that happens while the caller waits: <tt>->(line) { line.announce('…') }</tt>)
      # and the key after it is read.
      def readkey(**)
        key = @keys.shift
        key = @keys.shift.tap { key.call(self) } while key.respond_to?(:call)
        key
      end

      # Tells the caller +text+ as BBS::Session#announce does: through the
      # handler of #on_announce, else as a line. Returns +nil+.
      def announce(text)
        @announcer ? @announcer.call(text) : write("\r\n*** #{text} ***\r\n")
        nil
      end

      # The handler of #announce (see BBS::Session#on_announce).
      def on_announce(handler) = (@announcer = handler)

      # Everything written so far as text, one UTF-8 String (for
      # <tt>assert_includes</tt>); #raw has the bytes.
      def output = raw.force_encoding(Encoding::UTF_8)

      # Everything written so far, one binary String.
      def raw = @writes.join.b

      # The last write, +nil+ before the first.
      def last = @writes.last

      # Everything written since the last #take (or the start), one binary
      # String.
      def take
        bytes = @writes[@taken..].join.b
        @taken = @writes.size
        bytes
      end

      # No socket: a gateway cannot hand this line on.
      def line = nil

      # Turns mouse reporting on (only remembered).
      def enable_mouse = (@mouse = true)

      # Turns mouse reporting off (only remembered).
      def disable_mouse = (@mouse = false)

      # Whether mouse reporting is on.
      def mouse_on? = @mouse == true

      # The key of the line for rate limits: <tt>line:<session_id></tt>.
      def caller_key = "line:#{@session_id}"

      # Runs the block with the line (see BBS::Session#hand_over).
      def hand_over = yield(self)

      # The next line typed: the keys up to an +:enter+ joined, or +nil+
      # (a hang-up) when the keys run out first.
      def readline(**)
        typed = +''
        while (key = @keys.shift)
          return typed if key == :enter

          typed << key if key.is_a?(String)
        end
        nil
      end
    end
  end
end
