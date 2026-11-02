# frozen_string_literal: true

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

require_relative 'frame_buffer/wrap'
require_relative 'frame_buffer/ansi_text'
require_relative 'frame_buffer/drawing'
