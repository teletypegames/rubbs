# frozen_string_literal: true

require 'bbs'

module BBS
  # Helpers for the tests of a board, loaded with <tt>require 'bbs/test'</tt>
  # (not by <tt>require 'bbs'</tt>).
  module Test
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

      # A line with +keys+ to press.
      #
      # [petscii] whether the line is a C64 in PETSCII mode
      # [cols]    the terminal width (ignored on a PETSCII line)
      # [rows]    the terminal height (ignored on a PETSCII line)
      def initialize(keys: [], petscii: false, cols: 80, rows: 24, session_id: 'test')
        @keys       = keys.dup
        @petscii    = petscii
        @term_cols  = petscii ? Petscii::COLS : cols
        @term_rows  = petscii ? Petscii::ROWS : rows
        @session_id = session_id
        @writes     = []
        @taken      = 0
        @idle_seconds = nil
      end

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
      # none left. A +timeout:+ is taken and ignored.
      def readkey(**) = @keys.shift

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
