# frozen_string_literal: true

require_relative 'editor/layout'
require_relative 'editor/chrome'
require_relative 'editor/autosave'

module BBS
  # A full-screen text editor on a telnet line, for a modern terminal and a
  # Commodore 64 alike, for text longer than a BBS::Field holds: the cursor
  # keys move anywhere in the text, typing inserts at the cursor, DEL
  # (backspace) deletes before it, and the text wraps at word boundaries as
  # it is typed. The text and the cursor live in a BBS::TextBuffer, so the
  # editing keys do what they do in a BBS::Field.
  #
  # The editor owns the screen while it runs: a reversed title bar on the
  # first row, the text below it, and a row of key hints near the bottom.
  # It draws through a BBS::Cursor, which moves only relative to where it
  # left the cursor; it never writes into the last column or the last row,
  # which on a C64 would link or scroll lines.
  #
  # Keys:
  #
  # [cursor keys]        move; up and down keep the column
  # [HOME, END]          the start and the end of the screen row
  # [PgUp, PgDn]         a screenful up or down
  # [RETURN]             a new line; saves in a single-line editor
  # [DEL, backspace]     deletes the character before the cursor
  # [Delete]             deletes the character under the cursor
  # [RUN/STOP, ←, Esc]   asks on the bottom row: S saves, Q quits without
  #                      saving, any other key goes back to the text
  # [F1, Ctrl-S]         saves at once, where the terminal program lets the
  #                      key through (the Ultimate Term keeps F1 for itself)
  #
  #   text = BBS::Editor.new(session, text: post.body, title: 'BODY').run
  #   post.body = text if text
  #
  # With +autosave+ the text is handed to a block now and then while it is
  # edited, so the caller can keep it where a hang-up does not lose it. The
  # editor does not know where it goes:
  #
  #   BBS::Editor.new(session, text: body, title: 'BODY', autosave: 15) do |text|
  #     drafts.save(id, text)
  #   end.run
  class Editor
    include Autosave

    # The keys that save the text at once.
    SAVE_KEYS = %i[f1 ctrl_s].freeze
    # The keys that ask whether to save or quit.
    MENU_KEYS = %i[escape interrupt ctrl_q f7].freeze
    # The keys that move a row up or down, keeping the column.
    ROW_MOVES = { up: -1, down: 1 }.freeze
    # The keys that move a screenful up or down, keeping the column.
    PAGE_MOVES = { page_up: -1, page_down: 1 }.freeze

    # Creates an editor for +session+.
    #
    # [text]        the text to start from; lines end with LF
    # [title]       the text of the title bar
    # [single_line] one paragraph, wrapped on the screen: RETURN saves and
    #               line ends in +text+ become spaces
    # [max]         the most characters the text may hold (line ends
    #               count as one), or +nil+ for TextBuffer::MAX_LENGTH;
    #               the title bar counts them when it is given
    # [cols]        the screen width; default the session's
    # [rows]        the screen height; default the session's
    # [autosave]    seconds between autosaves, or +nil+ (the default) for
    #               none; it needs the block
    #
    # The block, with +autosave+, is called with the text (lines joined by
    # LF) every +autosave+ seconds while the caller types or thinks, and
    # once more when the caller hangs up, each time only when the text
    # changed since the last call; not when the caller saves or quits,
    # since #run returns then. An exception it raises is logged with
    # BBS.log and the editing goes on.
    #
    # The editor reads the keys with a timeout then, so it keeps the
    # session's idle limit itself: after <tt>session.idle_seconds</tt>
    # (Server::DEFAULT_TIMEOUT when unset) without a key it raises
    # IO::TimeoutError, as the line would.
    def initialize(session, text: '', title: '', single_line: false, max: nil, cols: nil, rows: nil,
                   autosave: nil, &on_autosave)
      @session = session
      @screen  = Cursor.new(session)
      @buffer  = TextBuffer.new(text, max: max, single_line: single_line)
      @single  = single_line
      @cols    = cols || session.term_cols
      @rows    = rows || session.term_rows
      @width   = @cols - 2
      @height  = @rows - 3
      @goal    = nil
      @top     = 0
      @chrome  = Chrome.new(@screen, title: title.to_s, single_line: single_line, max: max, cols: @cols, rows: @rows)
      @autosave    = on_autosave && autosave&.positive? ? autosave : nil
      @on_autosave = on_autosave
      @saved_text  = @buffer.text
    end

    # Runs the editor until the caller saves or quits, then leaves the
    # screen as it is; the caller draws the next one.
    #
    # Returns the text, lines joined by LF, when saved, and +nil+ when the
    # caller quit. Raises IOError, Errno::ECONNRESET or Errno::EPIPE when
    # the caller hangs up (after the last autosave) and IO::TimeoutError, an IOError, when an autosaving editor
    # sat idle past the session's limit.
    def run
      first_paint
      start_clock
      loop do
        key  = next_key
        done = finish(key)
        return done == :quit ? nil : @buffer.text if done

        handle(key)
        paint
        autosave if due?
      end
    rescue IOError, Errno::ECONNRESET, Errno::EPIPE
      autosave
      raise
    end

    private

    # What +key+ ends the editor with: +:save+, +:quit+, or +nil+ to go
    # on (also after the save-or-quit question was answered with another
    # key).
    def finish(key)
      return :save if SAVE_KEYS.include?(key) || (@single && key == :enter)

      MENU_KEYS.include?(key) ? menu : nil
    end

    def handle(key)
      @goal = nil unless ROW_MOVES.key?(key) || PAGE_MOVES.key?(key)
      return if @buffer.edit(key)
      return vertical(ROW_MOVES[key]) if ROW_MOVES.key?(key)
      return vertical(PAGE_MOVES[key] * @height) if PAGE_MOVES.key?(key)

      row_key(key)
    end

    # HOME and END: the start and the end of the screen row.
    def row_key(key)
      layout = self.layout
      row    = current_row(layout)
      pos    = { home: layout.rows[row][1], end: layout.row_end(row) }[key]
      @buffer.place(@buffer.line, pos) if pos
    end

    # Moves the cursor +delta+ screen rows, keeping its column (the goal).
    def vertical(delta)
      layout = self.layout
      now    = current_row(layout)
      @goal ||= @buffer.pos - layout.rows[now][1]
      target = (now + delta).clamp(0, layout.rows.size - 1)
      line, start, = layout.rows[target]
      @buffer.place(line, [start + @goal, layout.row_end(target)].min)
    end

    def layout = Layout.new(@buffer.lines, @width)

    def current_row(layout = self.layout) = layout.row_of(@buffer.line, @buffer.pos)

    # ── Screen ───────────────────────────────────────────────────────────

    def first_paint
      @shown = Array.new(@height)
      @session.write(@screen.clear << @chrome.title << @chrome.hints)
      paint
    end

    # Asks on the bottom row whether to save or quit: +:save+, +:quit+, or
    # +nil+ to go back to the text.
    def menu
      @session.write(@chrome.question)
      key = @screen.key
      @session.write(@chrome.hints)
      { 's' => :save, 'q' => :quit }[key.to_s.downcase]
    end

    # Draws the rows that changed, the count and the cursor, with the
    # cursor hidden meanwhile.
    def paint
      layout = self.layout
      row    = current_row(layout)
      scroll_to(row)
      out = (0...@height).map { |i| paint_row(i, layout.rows[@top + i]) }.join << @chrome.count(@buffer.length)
      @session.write("#{Ansi::HIDE_CURSOR}#{out}#{park(layout.rows[row], row)}#{Ansi::SHOW_CURSOR}")
    end

    # The cursor to its place in screen row +row+, the layout row +cells+.
    def park(cells, row) = @screen.move(2 + row - @top, 1 + @buffer.pos - cells[1])

    # Scrolls the text so screen row +row+ shows, to the middle when it
    # was off the screen.
    def scroll_to(row)
      @top = [row - (@height / 2), 0].max if row < @top || row >= @top + @height
    end

    # The bytes that draw screen row +index+ of the text, the layout row
    # +row+ (+nil+ past the end); nothing when it shows already.
    def paint_row(index, row)
      line, start, stop = row
      text = fit(@screen.cells(line.nil? ? '' : @buffer.lines[line][start, [stop - start, @width].min]), @width)
      return '' if @shown[index] == text

      @shown[index] = text
      out = @screen.move(2 + index, 1) << text
      @screen.wrote(@width)
      out
    end

    def fit(text, width) = text[0, width].ljust(width)
  end
end
