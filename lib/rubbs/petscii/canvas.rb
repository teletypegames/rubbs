# frozen_string_literal: true

module Rubbs
  module Petscii
    # The C64 screen as a grid of 40×25 cells, by default in the
    # uppercase/graphics character set, where the card suits, the balls,
    # the rounded corners, the diagonals and the quarter blocks live; with
    # <tt>charset: :lower</tt> in the lower/upper set, where text keeps its
    # case. It turns into raw PETSCII: the whole screen once (#frame), then
    # only what changes (#span, #patch, #diff, #update), because a C64 line
    # behind a modem is slow.
    #
    # It bypasses the PETSCII Encoder of the session, which speaks the
    # lowercase set: send its bytes with <tt>session.write_raw</tt>. Its
    # constants are the codes of Rubbs::Petscii as Integers (there they are
    # Strings, for the Encoder): one code table for both.
    #
    # A cell is drawn by #text from a Unicode string: letters, digits and
    # signs as they are (letters in capitals), and the graphics of GLYPHS and
    # GLYPHS_REVERSED by the character they look like. Colours are the codes
    # (+GREEN+ …) or their names in COLOR_NAMES (+:green+, +'light grey'+).
    #
    #   canvas = Rubbs::Petscii::Canvas.new
    #   canvas.text(0, 1, 'TTG CLUBHOUSE', :yellow)
    #   canvas.text(2, 1, '╭──╮', :light_blue)
    #   session.write_raw(canvas.frame)           # the whole screen, once
    #
    #   before = canvas.dup
    #   canvas.text(2, 2, '●', :red)
    #   session.write_raw(canvas.update(before))  # only the changed cell
    #
    # A screen of text in both cases, repainted by what changed:
    #
    #   shown  = nil
    #   canvas = Rubbs::Petscii::Canvas.new(charset: :lower)
    #   canvas.text(3, 1, 'Global Discovery', :light_green)
    #   session.write_raw(shown ? canvas.diff(shown) : canvas.frame)
    #   shown = canvas
    #
    # Byte sizes to aim for on a slow line: a whole screen of art about
    # 1.2 KB, one step of an animation under 200 bytes (#update and #diff
    # pick the cheaper of a patch and a frame).
    class Canvas
      # The rows of the C64 screen.
      ROWS = 25
      # The columns of the C64 screen.
      COLS = 40

      # PETSCII colour code: white.
      WHITE       = Petscii::WHITE.ord
      # PETSCII colour code: red.
      RED         = Petscii::RED.ord
      # PETSCII colour code: green.
      GREEN       = Petscii::GREEN.ord
      # PETSCII colour code: blue.
      BLUE        = Petscii::BLUE.ord
      # PETSCII colour code: orange.
      ORANGE      = Petscii::ORANGE.ord
      # PETSCII colour code: black.
      BLACK       = Petscii::BLACK.ord
      # PETSCII colour code: brown.
      BROWN       = Petscii::BROWN.ord
      # PETSCII colour code: light red.
      LIGHT_RED   = Petscii::LIGHT_RED.ord
      # PETSCII colour code: dark grey.
      DARK_GREY   = Petscii::DARK_GREY.ord
      # PETSCII colour code: medium grey.
      GREY        = Petscii::GREY.ord
      # PETSCII colour code: light green.
      LIGHT_GREEN = Petscii::LIGHT_GREEN.ord
      # PETSCII colour code: light blue.
      LIGHT_BLUE  = Petscii::LIGHT_BLUE.ord
      # PETSCII colour code: light grey.
      LIGHT_GREY  = Petscii::LIGHT_GREY.ord
      # PETSCII colour code: purple.
      PURPLE      = Petscii::PURPLE.ord
      # PETSCII colour code: yellow.
      YELLOW      = Petscii::YELLOW.ord
      # PETSCII colour code: cyan.
      CYAN        = Petscii::CYAN.ord

      # Control code: clears the screen and homes the cursor.
      CLEAR     = Petscii::CLEAR.ord
      # Control code: the cursor to the top left.
      HOME      = Petscii::HOME.ord
      # Control code: the cursor down a row.
      DOWN      = Petscii::DOWN.ord
      # Control code: the cursor up a row.
      UP        = Petscii::UP.ord
      # Control code: the cursor right a column.
      RIGHT     = Petscii::RIGHT.ord
      # Control code: the cursor left a column.
      LEFT      = Petscii::LEFT.ord
      # Control code: reverse video on.
      RVS_ON    = Petscii::RVS_ON.ord
      # Control code: reverse video off.
      RVS_OFF   = Petscii::RVS_OFF.ord
      # Control code: RETURN, the start of the next row with reverse off.
      CR        = 0x0d
      # Control code: the uppercase/graphics character set.
      UPPERCASE = Petscii::UPPERCASE.ord
      # Control code: the lowercase character set.
      LOWERCASE = Petscii::LOWERCASE.ord
      # The code of a space.
      SPACE     = 0x20

      # The sixteen colours by name, as the C64 calls them.
      COLOR_NAMES = {
        black:       BLACK,
        white:       WHITE,
        red:         RED,
        cyan:        CYAN,
        purple:      PURPLE,
        green:       GREEN,
        blue:        BLUE,
        yellow:      YELLOW,
        orange:      ORANGE,
        brown:       BROWN,
        light_red:   LIGHT_RED,
        dark_grey:   DARK_GREY,
        grey:        GREY,
        light_green: LIGHT_GREEN,
        light_blue:  LIGHT_BLUE,
        light_grey:  LIGHT_GREY
      }.freeze

      # The sixteen colours as [red, green, blue] (the palette of VICE and
      # the C64 wiki, the one the boards match accents against), by code.
      RGB = {
        BLACK       => [0, 0, 0],
        WHITE       => [255, 255, 255],
        RED         => [136, 0, 0],
        CYAN        => [170, 255, 238],
        PURPLE      => [204, 68, 204],
        GREEN       => [0, 204, 85],
        BLUE        => [0, 0, 170],
        YELLOW      => [238, 238, 119],
        ORANGE      => [221, 136, 85],
        BROWN       => [102, 68, 0],
        LIGHT_RED   => [255, 119, 119],
        DARK_GREY   => [51, 51, 51],
        GREY        => [119, 119, 119],
        LIGHT_GREEN => [170, 255, 102],
        LIGHT_BLUE  => [0, 136, 255],
        LIGHT_GREY  => [187, 187, 187]
      }.freeze

      # The graphics of the uppercase set by the Unicode character they look
      # like, as PETSCII codes: the shared Rubbs::Petscii::GRAPHICS and the
      # set's own Rubbs::Petscii::UPPERCASE_GRAPHICS.
      GLYPHS = Glyphs::GRAPHICS.merge(Glyphs::UPPERCASE_GRAPHICS).freeze
      # The graphics that are a code of GLYPHS in reverse video: the full
      # block a reversed space, the upper half a reversed lower half …
      GLYPHS_REVERSED = { '█' => 0x20, '▀' => 0xa2, '◢' => 0xa9, '◣' => 0xdf, '▐' => 0xa1 }.freeze
      # The PETSCII codes the lower/upper set shows differently from the
      # uppercase one: the capitals (0xc1-0xda, graphics in the uppercase
      # set), π, ◥ and the diagonals ◤ ◢ (0xa9, 0xdf), and the check mark
      # (0xba).
      LOWER_CHANGED = [*0xc1..0xda, 0xde, 0xdf, 0xa9, 0xba].freeze
      # The graphics of the lower/upper set by the Unicode character they
      # look like: GLYPHS without LOWER_CHANGED (the lines, the cross, the
      # blocks, ▒ and the 0xa0-0xbf graphics stay), and the set's own
      # Rubbs::Petscii::LOWERCASE_GRAPHICS.
      LOWER_GLYPHS = GLYPHS.reject { |_, code| LOWER_CHANGED.include?(code) }.merge(Glyphs::LOWERCASE_GRAPHICS).freeze
      # GLYPHS_REVERSED of the lower/upper set.
      LOWER_GLYPHS_REVERSED = GLYPHS_REVERSED.reject { |_, code| LOWER_CHANGED.include?(code) }.freeze
      # The two character sets a Canvas draws in: +:upper+
      # (uppercase/graphics) and +:lower+ (lower/upper).
      CHARSETS = %i[upper lower].freeze
      # The ASCII codes the uppercase set shows as they are (0x5c is £ there,
      # so the backslash is not among them).
      ASCII_SHOWN = [*0x20..0x5b, 0x5d].freeze

      # One cell: its PETSCII +code+, its colour code (+nil+ for none set)
      # and whether it is in reverse video (+rvs+).
      Cell = Struct.new(:code, :color, :rvs) do
        # Whether it shows anything: not a plain space.
        def visible? = code != SPACE || rvs

        # Whether it looks the same as +other+ on the screen: an invisible
        # cell looks the same in any colour.
        def looks_like?(other)
          return !other.visible? unless visible?

          code == other.code && rvs == other.rvs && color == other.color
        end
      end

      # The character set of the screen, +:upper+ or +:lower+: the one
      # #text draws in, #frame switches to and #to_s reads; the one it was
      # created with, or the one the last #feed left the screen in.
      attr_reader :charset

      # Creates an empty screen: every cell a space with no colour, in the
      # character set +charset+ (+:upper+, the uppercase/graphics set, or
      # +:lower+, the lower/upper set). Raises ArgumentError for another.
      def initialize(charset: :upper)
        raise ArgumentError, "not a character set: #{charset.inspect}" unless CHARSETS.include?(charset)

        @cells   = Array.new(ROWS) { Array.new(COLS) { blank } }
        @at      = [0, 0]
        @pen     = nil
        @rvs     = false
        @charset = charset
      end

      # A copy with its own cells, to compare with after drawing (#update).
      def initialize_copy(source)
        super
        @cells = source.cells_copy
        @at    = @at.dup
      end

      # Writes +text+ from +row+, +col+ (0-based) in +color+ (see ::color;
      # in the screen's #charset, see ::code;
      # +nil+ sends no colour, so the cell takes the colour printed before
      # it);
      # a character of GLYPHS_REVERSED, or every one with +rvs+, in reverse
      # video (a reversed glyph with +rvs+ shows plain). Cells off the
      # screen, and the last cell of the last row (printing there scrolls the
      # C64 screen), are left out.
      #
      # Returns +self+.
      def text(row, col, text, color, rvs: false)
        color = Canvas.color(color)
        text.each_char.with_index do |ch, i|
          c = col + i
          next unless inside?(row, c)

          code, reversed = Canvas.code(ch, @charset)
          @cells[row][c] = Cell.new(code, color, rvs ^ reversed)
        end
        self
      end

      # Sets the cell at +row+, +col+ to the PETSCII +code+ as it is, in
      # +color+ (see ::color), reversed with +rvs+; off the screen, and on
      # the last cell, nothing. Returns +self+.
      def put(row, col, code, color, rvs: false)
        @cells[row][col] = Cell.new(code, Canvas.color(color), rvs) if inside?(row, col)
        self
      end

      # Blanks +width+ cells of +row+ from +col+. Returns +self+.
      def clear(row, col, width)
        width.times { |i| @cells[row][col + i] = blank if inside?(row, col + i) }
        self
      end

      # The Cell at +row+, +col+, or +nil+ off the screen.
      def cell(row, col)
        return nil unless row.between?(0, ROWS - 1) && col.between?(0, COLS - 1)

        @cells[row][col]
      end

      # The positions, [row, col] each, where this screen looks different
      # from +before+ (another Canvas): see Cell#looks_like?.
      def changes(before)
        (0...ROWS).flat_map do |row|
          (0...COLS).filter_map { |col| [row, col] unless @cells[row][col].looks_like?(before.cell(row, col)) }
        end
      end

      # The screen as text, a line a row, each cell the Unicode character it
      # looks like in the screen's #charset (a reversed cell as it is
      # printed, not inverted); for tests and logs.
      def to_s
        @cells.map { |row| row.map { |c| Canvas.look(c.code, @charset) }.join.rstrip }.join("\n")
      end

      protected

      # A deep copy of the rows of cells.
      def cells_copy = @cells.map { |row| row.map(&:dup) }

      private

      def blank = Cell.new(SPACE, nil, false)

      def inside?(row, col) = row.between?(0, ROWS - 1) && col.between?(0, COLS - 1) && !(row == ROWS - 1 && col == COLS - 1)
    end
  end
end

require_relative 'canvas/output'
require_relative 'canvas/player'
require_relative 'canvas/lookup'
