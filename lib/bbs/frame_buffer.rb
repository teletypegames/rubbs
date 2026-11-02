# frozen_string_literal: true

require_relative 'frame_buffer/wrap'

module BBS
  # An off-screen grid of character cells, each holding one character and
  # the SGR escape sequence that styles it. Widgets and windows draw into a
  # frame buffer with 1-based coordinates; #diff then turns the changes
  # since the previous frame into the ANSI bytes to send to the terminal.
  #
  # Its class methods are rubbs' one set of tools for ANSI text: ::plain,
  # ::visible_width, ::clip_ansi and ::wrap_ansi (the one word-wrap).
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
    # SGR reset with no parameter, the short form of Ansi::RESET.
    SHORT_RESET = "\e[m"
    # The two SGR resets, the long form and the short one.
    RESETS = [Ansi::RESET, SHORT_RESET].freeze
    # A character a cell never holds: a C0 control, DEL, a C1 control or a
    # bidirectional control, any of which would move or restyle the caller's
    # screen behind the frame buffer's back.
    CONTROL_CHAR = /[\u0000-\u001F\u007F-\u009F#{Text::BIDI_CONTROLS}]/
    # One token of ANSI text: a CSI sequence (first group), a CSI sequence
    # cut off by the end of the text (second group) or one character
    # (third group).
    ANSI_TOKEN = /(#{Ansi::CSI_RE})|(\e\[[^A-Za-z~]*\z)|(.)/m
    # Box-drawing characters per frame style (+:single+, +:double+): the
    # corners +:tl+, +:tr+, +:bl+, +:br+ and the edges +:h+, +:v+.
    BOX_CHARS = {
      single: { tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│' },
      double: { tl: '╔', tr: '╗', bl: '╚', br: '╝', h: '═', v: '║' }
    }.freeze

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

    # Returns +text+ (anything with +to_s+) as UTF-8 without its ANSI
    # escape sequences: the one way rubbs strips colours from text.
    def self.plain(text) = self.text(text).gsub(Ansi::CSI_RE, '')

    # Returns the number of characters of +text+ left once its ANSI escape
    # sequences are removed.
    def self.visible_width(text) = plain(text).length

    # Returns +text+ cut so that at most +max_width+ characters are visible.
    # Escape sequences up to the cut are kept (they take no width); an
    # escape sequence the text cuts off ends it. An empty String when
    # +max_width+ is zero or less.
    def self.clip_ansi(text, max_width)
      out     = +''
      visible = 0
      self.text(text).scan(ANSI_TOKEN) do |seq, cut, char|
        break if cut || (char && visible >= max_width)

        out << (seq || char)
        visible += 1 if char
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
      visible_width(s) <= width ? [s] : Wrap.new(width).lines(s)
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

        put(ch, sgr) unless ch.match?(CONTROL_CHAR)
      end
    end

    # Writes +text+ from the cursor, interpreting its SGR sequences: they
    # add to +base_sgr+, the starting style, and a reset (<tt>\e[m</tt>,
    # <tt>\e[0m</tt>) returns to it. <tt>\e[nC</tt> writes +n+ styled
    # spaces. Other escape sequences and control characters (CONTROL_CHAR)
    # are skipped.
    def write_ansi(text, base_sgr: nil)
      sgr = base_sgr
      self.class.text(text).scan(ANSI_TOKEN) do |seq, _cut, char|
        if seq
          sgr = csi(seq, sgr, base_sgr)
        elsif char && !char.match?(CONTROL_CHAR)
          put(char, sgr)
        end
      end
    end

    # ── Drawing helpers (1-based coordinates) ────────────────────────────────

    # Fills the rectangle at +x+, +y+ of +width+ by +height+ cells with
    # +char+ in style +sgr+.
    def fill(x:, y:, width:, height:, sgr: nil, char: ' ')
      height.times { |r| hline(x: x, y: y + r, length: width, char: char, sgr: sgr) }
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

    # Draws a frame of +width+ by +height+ cells with its top left at +x+,
    # +y+. Does nothing when either side is under 2.
    #
    # [sgr]          style of the frame
    # [fill_sgr]     when given, the inside is cleared with spaces in this style
    # [style]        a BOX_CHARS key; an unknown one draws +:single+
    # [title]        text set into the top edge, clipped to fit
    # [title_sgr]    style of the title (defaults to +sgr+)
    # [title_indent] edge characters drawn before the title
    def box(x:, y:, width:, height:, sgr: nil, fill_sgr: nil, style: :single, title: nil, title_sgr: nil,
            title_indent: 0)
      return if width < 2 || height < 2

      g = BOX_CHARS[style] || BOX_CHARS[:single]
      top_edge(x, y, width, g, sgr, [title, title_sgr || sgr, [title_indent, 0].max])
      (1...height - 1).each { |r| box_side(x, y + r, width, g, sgr, fill_sgr) }
      hline(x: x, y: y + height - 1, length: 1, char: g[:bl], sgr: sgr)
      write(g[:h] * (width - 2), sgr: sgr)
      write(g[:br], sgr: sgr)
    end

    # Draws the drop shadow of a +width+ by +height+ rectangle at +x+, +y+:
    # two columns down its right side and one row under it, offset by one
    # row and two columns, in style +sgr+ (black background by default).
    def shadow(x:, y:, width:, height:, sgr: nil)
      sgr ||= Ansi::BG_BLACK
      if x + width < @cols
        height.times { |r| hline(x: x + width, y: y + 1 + r, length: 2, char: ' ', sgr: sgr) }
      end
      hline(x: x + 2, y: y + height, length: width, char: ' ', sgr: sgr) if y + height <= @rows
    end

    # Returns the ANSI byte String that turns a screen showing the frame
    # buffer +from+ into this one: only changed cells are written, with a
    # cursor move only where the next changed cell is not adjacent. Each
    # style change starts from a reset; the stream ends with a reset when
    # any styled cell was written. Both buffers must have the same size.
    def diff(from)
      out   = +''
      state = { sgr: :none, at: nil }
      changes(from).each { |r, c, cell| out << diff_cell(r, c, cell, state) }
      out << Ansi::RESET if state[:sgr] != :none && state[:sgr]
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

    # Acts on the CSI sequence +seq+ written in style +sgr+, and returns
    # the style after it: an SGR sequence adds to +sgr+ (a reset returns to
    # +base_sgr+), a cursor right writes styled spaces.
    def csi(seq, sgr, base_sgr)
      params = seq[2...-1]
      case seq[-1]
      when 'm' then ['', '0'].include?(params) ? base_sgr : "#{sgr}#{seq}"
      when 'C' then [params.to_i, 1].max.clamp(1, @cols).times { put(' ', sgr) } && sgr
      else sgr
      end
    end

    # The top edge of a box: the corners, and the title when there is one.
    def top_edge(x, y, width, g, sgr, (title, title_sgr, indent))
      inner = width - 2
      hline(x: x, y: y, length: 1, char: g[:tl], sgr: sgr)
      if title.to_s.empty?
        write(g[:h] * inner, sgr: sgr)
      else
        clipped = title[0, [inner - 2 - indent, 0].max]
        write("#{g[:h] * indent}#{g[:h]} ", sgr: sgr)
        write(clipped, sgr: title_sgr)
        write(g[:h] * [inner - indent - 2 - clipped.length, 0].max, sgr: sgr)
      end
      write(g[:tr], sgr: sgr)
    end

    # One row of a box's sides, its inside cleared with +fill_sgr+.
    def box_side(x, y, width, g, sgr, fill_sgr)
      hline(x: x, y: y, length: 1, char: g[:v], sgr: sgr)
      write(' ' * (width - 2), sgr: fill_sgr) if fill_sgr
      hline(x: x + width - 1, y: y, length: 1, char: g[:v], sgr: sgr)
    end

    # The cells that differ from +from+: [row, col, cell], 0-based.
    def changes(from)
      (0...@rows).flat_map do |r|
        (0...@cols).filter_map { |c| [r, c, @cells[r][c]] unless @cells[r][c] == from.cell_at(r, c) }
      end
    end

    # The bytes of one changed cell: a cursor move unless it follows the
    # last one, its style from a reset when it changes, its character.
    def diff_cell(row, col, cell, state)
      out = +''
      out << "#{Ansi::CSI}#{row + 1};#{col + 1}H" unless state[:at] == [row, col]
      out << Ansi::RESET << cell.sgr.to_s if cell.sgr != state[:sgr]
      state[:sgr] = cell.sgr
      state[:at]  = [row, col + 1]
      out << cell.char
    end
  end
end
