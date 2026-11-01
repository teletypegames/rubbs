# frozen_string_literal: true

module BBS
  # Where the cursor of a session is, as far as the code drawing on it
  # knows, and the escape sequences that move it from there: the drawing
  # primitives BBS::Field and BBS::Editor share.
  #
  # Moves are relative, from the position the cursor was last moved to or
  # written up to, so a C64 never gets HOME. On a PETSCII line the cursor
  # goes down with RETURN rather than cursor down: what is drawn works the
  # same through the C64's screen editor and through a terminal program
  # that handles the control codes itself.
  #
  # The methods return the bytes to write rather than writing them, so a
  # caller sends a whole screen update at once.
  class Cursor
    # The row of the cursor, 1-based (relative to where counting began).
    attr_reader :row
    # The column of the cursor, 1-based (relative to where counting began).
    attr_reader :col

    # Starts counting at +row+, +col+ on the screen of +session+.
    def initialize(session, row: 1, col: 1)
      @session = session
      @petscii = session.respond_to?(:petscii?) && session.petscii?
      @row     = row
      @col     = col
    end

    # True when the session is a PETSCII line (a C64).
    def petscii? = @petscii

    # Reads a key from the session (see BBS::Telnet#readkey). Raises
    # IOError when the caller hangs up.
    def key
      key = @session.readkey
      raise IOError, 'the caller hung up' if key.nil?

      key
    end

    # Returns the bytes that reset the colours, clear the screen and home
    # the cursor (on a C64 CLR homes it by itself), and counts from 1, 1.
    def clear
      @row = 1
      @col = 1
      @petscii ? "#{Ansi::RESET}#{Ansi::CLEAR_SCREEN}" : "#{Ansi::RESET}#{Ansi::CLEAR}"
    end

    # Returns the bytes that move the cursor to +row+, +col+.
    def move(row, col)
      out = +''
      if row > @row && @petscii
        out << (Ansi::CRLF * (row - @row))
        @col = 1
      elsif row != @row
        out << (row > @row ? "#{Ansi::CSI}#{row - @row}B" : "#{Ansi::CSI}#{@row - row}A")
      end
      out << (col > @col ? "#{Ansi::CSI}#{col - @col}C" : "#{Ansi::CSI}#{@col - col}D") unless col == @col
      @row = row
      @col = col
      out
    end

    # Counts +count+ characters written at the cursor: it is that many
    # columns further right.
    def wrote(count)
      @col += count
    end

    # +text+ as the screen shows it, one cell a character: on a C64 a
    # character with no single PETSCII glyph becomes ? (see
    # BBS::Petscii.cell), so the columns stay where they are counted.
    def cells(text)
      @petscii ? text.each_char.map { |c| Petscii.cell(c) }.join : text
    end
  end
end
