# frozen_string_literal: true

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
  class Editor
    # The keys that save the text at once.
    SAVE_KEYS = %i[f1 ctrl_s].freeze
    # The keys that ask whether to save or quit.
    MENU_KEYS = %i[escape interrupt ctrl_q f7].freeze
    # SGR: reverse video on, for the title bar, the hint row and the count.
    REVERSE     = "\e[7m"
    # SGR: reverse video off.
    REVERSE_OFF = "\e[27m"

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
    def initialize(session, text: '', title: '', single_line: false, max: nil, cols: nil, rows: nil)
      @session = session
      @screen  = Cursor.new(session)
      @buffer  = TextBuffer.new(text, max: max, single_line: single_line)
      @title   = title.to_s
      @single  = single_line
      @max     = max
      @cols    = cols || session.term_cols
      @rows    = rows || session.term_rows
      @width   = @cols - 2
      @height  = @rows - 3
      @goal    = nil
      @top     = 0
    end

    # Runs the editor until the caller saves or quits, then leaves the
    # screen as it is; the caller draws the next one.
    #
    # Returns the text, lines joined by LF, when saved, and +nil+ when the
    # caller quit. Raises IOError when the caller hangs up.
    def run
      first_paint
      loop do
        key = @screen.key
        return @buffer.text if SAVE_KEYS.include?(key) || (@single && key == :enter)

        if MENU_KEYS.include?(key)
          case menu
          when :save then return @buffer.text
          when :quit then return nil
          end
        end

        handle(key)
        paint
      end
    end

    private

    def handle(key)
      @goal = nil unless %i[up down page_up page_down].include?(key)
      return if @buffer.edit(key)

      case key
      when :up        then vertical(-1)
      when :down      then vertical(1)
      when :page_up   then vertical(-@height)
      when :page_down then vertical(@height)
      when :home      then @buffer.place(@buffer.line, layout[current_row][1])
      when :end       then @buffer.place(@buffer.line, row_end(current_row))
      end
    end

    def vertical(delta)
      rows = layout
      now  = current_row(rows)
      @goal ||= @buffer.pos - rows[now][1]
      target = (now + delta).clamp(0, rows.size - 1)
      line, start, = rows[target]
      @buffer.place(line, [start + @goal, row_end(target, rows)].min)
    end

    # ── Layout ───────────────────────────────────────────────────────────

    # The screen rows of the text: <tt>[line, start, stop]</tt>, the
    # characters <tt>start...stop</tt> of line +line+.
    def layout
      @buffer.lines.each_with_index.flat_map do |text, i|
        starts = wrap(text)
        starts.each_with_index.map { |s, j| [i, s, starts[j + 1] || text.length] }
      end
    end

    # Where the rows of +text+ start: a row breaks after the last space
    # that fits, or at the width when a word is longer than a row. A row
    # may end in one space beyond the width, which takes no room.
    def wrap(text)
      starts = [0]
      pos    = 0
      while text.length - pos > @width
        space = text.rindex(' ', pos + @width)
        pos   = space && space >= pos ? space + 1 : pos + @width
        starts << pos
      end
      starts
    end

    def current_row(rows = layout)
      rows.rindex { |line, start, _| line == @buffer.line && start <= @buffer.pos } || 0
    end

    # The last cursor position on a row: its end on the last row of a line,
    # before its last character otherwise, as that position is the next
    # row's start.
    def row_end(index, rows = layout)
      line, start, stop = rows[index]
      last = rows[index + 1].nil? || rows[index + 1][0] != line
      last ? stop : [stop - 1, start].max
    end

    # ── Screen ───────────────────────────────────────────────────────────

    def first_paint
      @shown  = Array.new(@height)
      @status = nil
      out = @screen.clear
      out << "#{REVERSE}#{fit(" #{@title}", @cols - 1)}#{REVERSE_OFF}"
      @screen.wrote(@cols - 1)
      out << bottom(hints)
      @session.write(out)
      paint
    end

    def hints
      menu  = @screen.petscii? ? 'STOP/←' : 'Esc'
      enter = @screen.petscii? ? 'RETURN' : 'Enter'
      @single ? "#{enter} save  #{menu} quit" : "#{menu}: save or quit"
    end

    # Asks on the bottom row whether to save or quit: +:save+, +:quit+, or
    # +nil+ to go back to the text.
    def menu
      enter = @screen.petscii? ? 'RETURN' : 'Enter'
      @session.write(bottom("S save  Q quit  #{enter} back"))
      key = @screen.key
      @session.write(bottom(hints))
      { 's' => :save, 'q' => :quit }[key.to_s.downcase]
    end

    # The bottom row in reverse, written over with +text+.
    def bottom(text)
      out = @screen.move(@rows - 1, 1) << "#{REVERSE}#{fit(" #{text}", @cols - 1)}#{REVERSE_OFF}"
      @screen.wrote(@cols - 1)
      out
    end

    def paint
      rows = layout
      row  = current_row(rows)
      @top = [row - (@height / 2), 0].max if row < @top || row >= @top + @height
      out = +Ansi::HIDE_CURSOR
      @height.times do |i|
        line, start, stop = rows[@top + i]
        text = line.nil? ? '' : @buffer.lines[line][start, [stop - start, @width].min]
        text = fit(@screen.cells(text), @width)
        next if @shown[i] == text

        out << @screen.move(2 + i, 1) << text
        @screen.wrote(@width)
        @shown[i] = text
      end
      out << status
      out << @screen.move(2 + row - @top, 1 + @buffer.pos - rows[row][1])
      out << Ansi::SHOW_CURSOR
      @session.write(out)
    end

    # The count of characters at the right of the title bar, when there
    # is a limit to it.
    def status
      return '' unless @max

      count = "#{@buffer.length}/#{@max} ".rjust("#{@max}/#{@max} ".length)
      return '' if count == @status

      @status = count
      out = @screen.move(1, @cols - 1 - count.length)
      @screen.wrote(count.length + 1)
      "#{out}#{REVERSE} #{count}#{REVERSE_OFF}"
    end

    def fit(text, width) = text[0, width].ljust(width)
  end
end
