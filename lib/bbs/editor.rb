# frozen_string_literal: true

module BBS
  # A full-screen text editor on a telnet line, for a modern terminal and a
  # Commodore 64 alike: the cursor keys move anywhere in the text, typing
  # inserts at the cursor, DEL (backspace) deletes before it, and the text
  # wraps at word boundaries as it is typed.
  #
  # The editor owns the screen while it runs: a reversed title bar on the
  # first row, the text below it, and a row of key hints near the bottom. It
  # moves the cursor only relative to where it left it, and on a C64 down
  # with RETURN, so the line carries no HOME (0x13, XOFF) and no cursor down
  # (0x11, XON); it never writes into the last column or the last row, which
  # on a C64 would link or scroll lines.
  #
  # Keys:
  #
  # [cursor keys]        move; up and down keep the column
  # [HOME, END]          the start and the end of the screen row
  # [PgUp, PgDn]         a screenful up or down
  # [RETURN]             a new line; saves in a single-line editor
  # [DEL, backspace]     deletes the character before the cursor
  # [Delete]             deletes the character under the cursor
  # [F1, Ctrl-S]         saves
  # [RUN/STOP, ←, Esc, F7] asks on the bottom row: S saves, Q quits without
  #                      saving, any other key goes back to the text; a
  #                      terminal program may keep the function keys to
  #                      itself, these are plain keys
  #
  #   text = BBS::Editor.new(session, text: post.body, title: 'BODY').run
  #   post.body = text if text
  class Editor
    # The keys that save the text.
    SAVE_KEYS = %i[f1 ctrl_s].freeze
    # The keys that ask whether to save or quit.
    MENU_KEYS = %i[f7 escape ctrl_q interrupt].freeze

    # Creates an editor for +session+.
    #
    # [text]        the text to start from; lines end with LF
    # [title]       the text of the title bar
    # [single_line] one line of text, wrapped on the screen: RETURN saves
    #               and line ends in +text+ become spaces
    # [max]         the most characters the text may hold (line ends
    #               count as one), or +nil+ for no limit
    # [cols]        the screen width; default the session's
    # [rows]        the screen height; default the session's
    def initialize(session, text: '', title: '', single_line: false, max: nil, cols: nil, rows: nil)
      @session = session
      @petscii = session.respond_to?(:petscii?) && session.petscii?
      @title   = title.to_s
      @single  = single_line
      @max     = max
      @cols    = cols || session.term_cols
      @rows    = rows || session.term_rows
      @width   = @cols - 2
      @height  = @rows - 3
      text     = text.to_s.gsub("\r\n", "\n").tr("\t\r", '  ')
      text     = text.tr("\n", ' ') if @single
      @lines   = text.split("\n", -1).map(&:dup)
      @lines   = [+''] if @lines.empty?
      @line    = @lines.size - 1
      @pos     = @lines.last.length
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
        key = @session.readkey
        raise IOError, 'the caller hung up' if key.nil?

        return @lines.join("\n") if SAVE_KEYS.include?(key) || (@single && key == :enter)
        if MENU_KEYS.include?(key)
          case menu
          when :save then return @lines.join("\n")
          when :quit then return nil
          end
        end

        handle(key)
        paint
      end
    end

    private

    def handle(key)
      vertical = %i[up down page_up page_down].include?(key)
      @goal = nil unless vertical
      case key
      when :left      then left
      when :right     then right
      when :up        then vertical(-1)
      when :down      then vertical(1)
      when :page_up   then vertical(-@height)
      when :page_down then vertical(@height)
      when :home      then @pos = row_start(current_row)
      when :end       then @pos = row_end(current_row)
      when :enter     then split_line
      when :backspace then backspace
      when :delete    then delete
      when String     then insert(key)
      end
    end

    # ── Editing ──────────────────────────────────────────────────────────

    def length = @lines.sum(&:length) + @lines.size - 1

    def insert(char)
      return if @max && length >= @max
      return unless char.match?(/\A[[:print:]]\z/)

      @lines[@line].insert(@pos, char)
      @pos += 1
    end

    def split_line
      return if @max && length >= @max

      rest = @lines[@line].slice!(@pos..)
      @lines.insert(@line + 1, rest)
      @line += 1
      @pos   = 0
    end

    def backspace
      if @pos.positive?
        @lines[@line].slice!(@pos - 1)
        @pos -= 1
      elsif @line.positive?
        @pos = @lines[@line - 1].length
        @lines[@line - 1] << @lines.delete_at(@line)
        @line -= 1
      end
    end

    def delete
      if @pos < @lines[@line].length
        @lines[@line].slice!(@pos)
      elsif @line < @lines.size - 1
        @lines[@line] << @lines.delete_at(@line + 1)
      end
    end

    def left
      if @pos.positive?
        @pos -= 1
      elsif @line.positive?
        @line -= 1
        @pos = @lines[@line].length
      end
    end

    def right
      if @pos < @lines[@line].length
        @pos += 1
      elsif @line < @lines.size - 1
        @line += 1
        @pos = 0
      end
    end

    def vertical(delta)
      rows = layout
      now  = current_row(rows)
      @goal ||= @pos - rows[now][1]
      target = (now + delta).clamp(0, rows.size - 1)
      line, start, = rows[target]
      @line = line
      @pos  = [start + @goal, row_end(target, rows)].min
    end

    # ── Layout ───────────────────────────────────────────────────────────

    # The screen rows of the text: <tt>[line, start, stop]</tt>, the
    # characters <tt>start...stop</tt> of line +line+.
    def layout
      @lines.each_with_index.flat_map do |text, i|
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
      rows.rindex { |line, start, _| line == @line && start <= @pos } || 0
    end

    def row_start(index, rows = layout) = rows[index][1]

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
      @shown = Array.new(@height)
      @at    = [1, 1]
      out = +"\e[0m\e[2J"
      out << "\e[H" unless @petscii
      out << "\e[7m#{fit(" #{@title}", @cols - 1)}\e[27m"
      @at = [1, @cols]
      out << bottom(hints)
      @status = nil
      @session.write(out)
      paint
    end

    # Asks on the bottom row whether to save or quit: +:save+, +:quit+, or
    # +nil+ to go back to the text.
    def menu
      enter = @petscii ? 'RETURN' : 'Enter'
      @session.write(bottom("S save  Q quit  #{enter} back"))
      key = @session.readkey
      raise IOError, 'the caller hung up' if key.nil?

      @session.write(bottom(hints))
      { 's' => :save, 'q' => :quit }[key.to_s.downcase]
    end

    # The bottom row in reverse, written over with +text+.
    def bottom(text)
      out = move(@rows - 1, 1) << "\e[7m#{fit(" #{text}", @cols - 1)}\e[27m"
      @at = [@rows - 1, @cols]
      out
    end

    def hints
      menu = @petscii ? 'STOP/←' : 'Esc'
      return "RETURN save  #{menu} quit" if @single && @petscii
      return "Enter save  #{menu} quit" if @single

      "#{menu}: save or quit"
    end

    def paint
      rows = layout
      row  = current_row(rows)
      @top = [row - (@height / 2), 0].max if row < @top || row >= @top + @height
      out = +"\e[?25l"
      @height.times do |i|
        line, start, stop = rows[@top + i]
        text = line.nil? ? '' : @lines[line][start, [stop - start, @width].min]
        text = fit(text.each_char.map { |c| cell(c) }.join, @width)
        next if @shown[i] == text

        out << move(2 + i, 1) << text
        @at = [2 + i, 1 + @width]
        @shown[i] = text
      end
      out << status
      out << move(2 + row - @top, 1 + @pos - rows[row][1])
      out << "\e[?25h"
      @session.write(out)
    end

    # The count of characters at the right of the title bar, when there
    # is a limit to it.
    def status
      return '' unless @max

      count = "#{length}/#{@max} ".rjust("#{@max}/#{@max} ".length)
      return '' if count == @status

      @status = count
      out = move(1, @cols - 1 - count.length)
      @at = [1, @cols]
      "#{out}\e[7m #{count}\e[27m"
    end

    # The cursor from where it is to +row+, +col+. A C64 goes down with
    # RETURN, never with cursor down: that is 0x11, XON, which a terminal on
    # software flow control takes out of the line.
    def move(row, col)
      r, c = @at
      out = +''
      if row > r && @petscii
        out << ("\r\n" * (row - r))
        c = 1
      elsif row != r
        out << (row > r ? "\e[#{row - r}B" : "\e[#{r - row}A")
      end
      out << (col > c ? "\e[#{col - c}C" : "\e[#{c - col}D") unless col == c
      @at = [row, col]
      out
    end

    def fit(text, width) = text[0, width].ljust(width)

    # The character as the screen shows it in one cell: on a C64 a
    # character that has no single PETSCII glyph shows as ?, so the columns
    # stay where the editor counts them.
    def cell(char)
      return char unless @petscii
      return char if char.match?(/\A[ -~£]\z/)

      glyph = Petscii::GLYPHS[char]
      return char if glyph && glyph.length == 1

      base = char.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '')
      base.length == 1 && base.ascii_only? ? char : '?'
    end
  end
end
