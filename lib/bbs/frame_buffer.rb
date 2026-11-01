# frozen_string_literal: true

module BBS
  # An off-screen grid of character cells, each holding one character and
  # the SGR escape sequence that styles it. Widgets and windows draw into a
  # frame buffer with 1-based coordinates; #diff then turns the changes
  # since the previous frame into the ANSI bytes to send to the terminal.
  #
  #   buf = BBS::FrameBuffer.new(80, 24)
  #   buf.box(x: 1, y: 1, width: 20, height: 5, title: 'Hello')
  #   session.write(buf.diff(BBS::FrameBuffer.new(80, 24)))
  #
  # Anything drawn outside the grid is clipped.
  class FrameBuffer
    # One screen cell: +char+ is the character shown, +sgr+ the SGR escape
    # sequence that styles it (+nil+ for the terminal default).
    Cell = Struct.new(:char, :sgr)
    # The empty cell a cleared buffer is filled with: a space, no style.
    BLANK = Cell.new(' ', nil).freeze

    # Matches one CSI escape sequence (<tt>ESC [</tt> parameters and a final
    # letter or <tt>~</tt>), used to strip styling when measuring text.
    ANSI_ESC_RE = Ansi::CSI_RE
    # SGR reset with no parameter, the short form of Ansi::RESET.
    SHORT_RESET = "\e[m"
    # One token of word wrapping: a CSI sequence, a word, or a run of
    # whitespace.
    WRAP_TOKEN_RE = /(\e\[[\d;]*[A-Za-z~]|[^\s\e]+|\s+)/
    # A token that is whitespace only.
    BLANK_RE = /\A\s+\z/
    # A character a cell never holds: a C0 control, DEL, a C1 control or a
    # bidirectional control, any of which would move or restyle the caller's
    # screen behind the frame buffer's back.
    CONTROL_CHAR = /[\u0000-\u001F\u007F-\u009F#{Text::BIDI_CONTROLS}]/

    # Returns +value+ as a UTF-8 String a regexp can read: a binary String
    # is taken as UTF-8, another encoding is converted, and invalid bytes
    # become <tt>?</tt>.
    def self.text(value)
      s = value.to_s
      s = utf8(s) unless s.encoding == Encoding::UTF_8
      s.valid_encoding? ? s : s.scrub('?')
    end

    # Returns +s+ in UTF-8: bytes of a binary String as they are, another
    # encoding converted (what does not convert becomes <tt>?</tt>).
    def self.utf8(s)
      return s.dup.force_encoding(Encoding::UTF_8) if s.encoding == Encoding::BINARY

      s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
    end

    # Returns the number of characters of +text+ left once its ANSI escape
    # sequences are removed.
    def self.visible_width(text)
      self.text(text).gsub(ANSI_ESC_RE, '').length
    end

    # Returns +text+ cut so that at most +max_width+ characters are visible.
    # Escape sequences up to the cut are kept (they take no width); an empty
    # String when +max_width+ is zero or less.
    def self.clip_ansi(text, max_width)
      return '' if max_width <= 0
      out     = +''
      visible = 0
      i       = 0
      s       = self.text(text)
      len     = s.length
      while i < len
        if s[i] == Ansi::ESC && i + 1 < len && s[i + 1] == Ansi::CSI_BYTE
          j = i + 2
          j += 1 while j < len && !s[j].match?(Ansi::CSI_FINAL)
          break if j >= len
          out << s[i..j]
          i = j + 1
          next
        end
        break if visible >= max_width
        out << s[i]
        visible += 1
        i += 1
      end
      out
    end

    # Word-wraps the ANSI-styled +text+ to lines of at most +width+ visible
    # characters and returns them as an Array of Strings, with trailing
    # spaces removed. A word longer than +width+ stays on a line of its own.
    #
    # The style is carried across wrapped lines: when an SGR sequence is
    # active at a wrap point, the next line starts with that sequence again.
    # Returns <tt>['']</tt> when +width+ is zero or less.
    def self.wrap_ansi(text, width)
      return [''] if width <= 0
      s = self.text(text)
      return [s] if visible_width(s) <= width

      lines       = []
      cur         = +''
      cur_visible = 0
      active_sgr  = nil

      flush = lambda do
        lines << cur.rstrip
        cur = +''
        cur_visible = 0
        cur << active_sgr if active_sgr
      end

      s.scan(WRAP_TOKEN_RE) do |(tok)|
        if tok.start_with?(Ansi::ESC)
          active_sgr = [Ansi::RESET, SHORT_RESET].include?(tok) ? nil : tok
          cur << tok
          next
        end

        tok_visible = tok.gsub(ANSI_ESC_RE, '').length

        if tok.match?(BLANK_RE)
          if cur_visible == 0
            cur << tok
            cur_visible += tok_visible
          elsif cur_visible + tok_visible <= width
            cur << tok
            cur_visible += tok_visible
          else
            flush.call
          end
        else
          flush.call if cur_visible + tok_visible > width && cur_visible > 0
          cur << tok
          cur_visible += tok_visible
        end
      end

      lines << cur.rstrip unless cur.empty?
      lines.empty? ? [''] : lines
    end

    # The width (+cols+) and height (+rows+) of the grid in cells.
    attr_reader :cols, :rows

    # Creates a blank buffer of +cols+ by +rows+ cells with the cursor at the
    # top left.
    def initialize(cols, rows)
      @cols = cols
      @rows = rows
      clear
    end

    # Fills every cell with BLANK and moves the cursor to the top left.
    def clear
      @cells = Array.new(@rows) { Array.new(@cols) { BLANK } }
      @cx    = 0
      @cy    = 0
    end

    # Moves the cursor to column +col+, row +row+ (1-based). Off-screen
    # positions are kept as they are: whatever is written there is clipped,
    # not piled up in the last column or row.
    def move(col, row)
      @cx = col - 1
      @cy = row - 1
    end

    # Writes +text+ character by character from the cursor with style +sgr+,
    # advancing the cursor. Control characters (CONTROL_CHAR, escape
    # sequences among them) are dropped and take no cell; characters off the
    # grid are dropped.
    def write(text, sgr: nil)
      self.class.text(text).each_char do |ch|
        break if @cy >= @rows
        next if ch.match?(CONTROL_CHAR)

        put(ch, sgr)
      end
    end

    # Writes +text+ from the cursor, interpreting the escape sequences in it.
    #
    # [base_sgr] the starting style; an embedded <tt>\e[...m</tt> adds to it
    #            and a reset (<tt>\e[m</tt>, <tt>\e[0m</tt>) returns to it
    # [cursor]   honour <tt>\e[row;colH</tt> cursor moves (a TUI page); off by
    #            default so content in a widget cannot jump out of it
    #
    # <tt>\e[nC</tt> writes +n+ styled spaces. Other escape sequences and
    # control characters (CONTROL_CHAR) are skipped.
    def write_ansi(text, base_sgr: nil, cursor: false)
      cur_sgr = base_sgr
      s       = text.to_s
      s       = s.scrub('?') unless s.valid_encoding?
      i       = 0
      len     = s.length

      while i < len
        ch = s[i]

        if ch == Ansi::ESC && i + 1 < len && s[i + 1] == Ansi::CSI_BYTE
          j = i + 2
          j += 1 while j < len && !s[j].match?(Ansi::CSI_LETTER)

          if j < len
            term  = s[j]
            inner = s[(i + 2)...j]

            case term
            when 'm'
              seq     = s[i..j]
              cur_sgr = ['', '0'].include?(inner) ? base_sgr : "#{cur_sgr}#{seq}"
            when 'C'
              [inner.to_i, 1].max.clamp(1, @cols).times do
                @cells[@cy][@cx] = Cell.new(' ', cur_sgr) if visible?
                @cx += 1
              end
            when 'H', 'f'
              if cursor
                parts = inner.split(';')
                move([parts[1].to_i, 1].max, [parts[0].to_i, 1].max)
              end
            end

            i = j + 1
          else
            i += 1
          end
        elsif !ch.match?(CONTROL_CHAR)
          put(ch, cur_sgr)
          i += 1
        else
          i += 1
        end
      end
    end

    # ── Drawing helpers (1-based coordinates) ────────────────────────────────

    # Fills the rectangle at +x+, +y+ of +width+ by +height+ cells with
    # +char+ in style +sgr+.
    def fill(x:, y:, width:, height:, sgr: nil, char: ' ')
      height.times do |r|
        move(x, y + r)
        write(char * [width, 0].max, sgr: sgr)
      end
    end

    # Draws a horizontal line of +length+ +char+ characters from +x+, +y+
    # in style +sgr+.
    def hline(x:, y:, length:, char: '─', sgr: nil)
      move(x, y)
      write(char * [length, 0].max, sgr: sgr)
    end

    # Draws a vertical line of +length+ +char+ characters down from +x+, +y+
    # in style +sgr+.
    def vline(x:, y:, length:, char: '│', sgr: nil)
      length.times do |r|
        move(x, y + r)
        write(char, sgr: sgr)
      end
    end

    # Box-drawing characters per frame style (+:single+, +:double+): the
    # corners +:tl+, +:tr+, +:bl+, +:br+ and the edges +:h+, +:v+.
    BOX_CHARS = {
      single: { tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│' },
      double: { tl: '╔', tr: '╗', bl: '╚', br: '╝', h: '═', v: '║' }
    }.freeze

    # Draws a frame of +width+ by +height+ cells with its top left at +x+,
    # +y+. Does nothing when either side is under 2.
    #
    # [sgr]          style of the frame
    # [fill_sgr]     when given, the inside is cleared with spaces in this style
    # [style]        a BOX_CHARS key; an unknown one draws +:single+
    # [title]        text set into the top edge, clipped to fit
    # [title_sgr]    style of the title (defaults to +sgr+)
    # [title_indent] edge characters drawn before the title
    def box(x:, y:, width:, height:, sgr: nil, fill_sgr: nil, style: :single, title: nil, title_sgr: nil, title_indent: 0)
      return if width < 2 || height < 2
      g  = BOX_CHARS[style] || BOX_CHARS[:single]
      iw = width - 2

      move(x, y)
      write(g[:tl], sgr: sgr)
      if title && title.length > 0
        indent = [title_indent, 0].max
        title_max = [iw - 2 - indent, 0].max
        clipped   = title[0, title_max]
        write(g[:h] * indent, sgr: sgr) if indent > 0
        prefix = "#{g[:h]} "
        write(prefix, sgr: sgr)
        write(clipped, sgr: title_sgr || sgr)
        rest = iw - indent - prefix.length - clipped.length
        write(g[:h] * [rest, 0].max, sgr: sgr) if rest > 0
      else
        write(g[:h] * iw, sgr: sgr)
      end
      write(g[:tr], sgr: sgr)

      (1...height - 1).each do |r|
        move(x, y + r)
        write(g[:v], sgr: sgr)
        write(' ' * iw, sgr: fill_sgr) if fill_sgr
        move(x + width - 1, y + r)
        write(g[:v], sgr: sgr)
      end

      move(x, y + height - 1)
      write(g[:bl], sgr: sgr)
      write(g[:h] * iw, sgr: sgr)
      write(g[:br], sgr: sgr)
    end

    # Draws the drop shadow of a +width+ by +height+ rectangle at +x+, +y+:
    # two columns down its right side and one row under it, offset by one
    # row and two columns, in style +sgr+ (black background by default).
    def shadow(x:, y:, width:, height:, sgr: nil)
      sgr ||= Ansi::BG_BLACK
      # right edge
      height.times do |r|
        move(x + width, y + 1 + r)
        write('  ', sgr: sgr) if x + width < @cols
      end
      # bottom edge
      move(x + 2, y + height)
      write(' ' * [width, 0].max, sgr: sgr) if y + height <= @rows
    end

    # Returns the ANSI byte String that turns a screen showing the frame
    # buffer +from+ into this one: only changed cells are written, with a
    # cursor move only where the next changed cell is not adjacent. Each
    # style change starts from a reset; the stream ends with a reset when
    # any styled cell was written. Both buffers must have the same size.
    def diff(from)
      out     = +''
      cur_sgr = :_none
      exp_r   = nil
      exp_c   = nil

      @rows.times do |r|
        @cols.times do |c|
          nc = @cells[r][c]
          oc = from.cell_at(r, c)
          next if nc == oc

          out << "#{Ansi::CSI}#{r + 1};#{c + 1}H" unless r == exp_r && c == exp_c

          # Each style starts from a reset, so no attribute of the cell
          # painted before it carries over.
          if nc.sgr != cur_sgr
            out << Ansi::RESET << nc.sgr.to_s
            cur_sgr = nc.sgr
          end

          out << nc.char
          exp_r = r
          exp_c = c + 1
        end
      end

      out << Ansi::RESET if cur_sgr != :_none && cur_sgr
      out
    end

    protected

    # Returns whether the cursor is inside the grid.
    def visible? = @cy >= 0 && @cy < @rows && @cx >= 0 && @cx < @cols

    # Returns the Cell at the 0-based +row+ and +col+.
    def cell_at(row, col)
      @cells[row][col]
    end

    private

    def put(char, sgr)
      @cells[@cy][@cx] = Cell.new(char, sgr) if visible?
      @cx += 1
    end
  end
end
