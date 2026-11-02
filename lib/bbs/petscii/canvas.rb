# frozen_string_literal: true

module BBS
  module Petscii
    # The C64 screen as a grid of 40×25 cells in the uppercase/graphics
    # character set, where the card suits, the balls, the rounded corners,
    # the diagonals and the quarter blocks live. It turns into raw PETSCII:
    # the whole screen once (#frame), then only what changes (#span, #patch,
    # #update), because a C64 line behind a modem is slow.
    #
    # It bypasses the PETSCII Encoder of the session, which speaks the
    # lowercase set: send its bytes with <tt>session.write_raw</tt>. Its
    # constants are the codes of BBS::Petscii as Integers (there they are
    # Strings, for the Encoder): one code table for both.
    #
    # A cell is drawn by #text from a Unicode string: letters, digits and
    # signs as they are (letters in capitals), and the graphics of GLYPHS and
    # GLYPHS_REVERSED by the character they look like. Colours are the codes
    # (+GREEN+ …) or their names in COLOR_NAMES (+:green+, +'light grey'+).
    #
    #   canvas = BBS::Petscii::Canvas.new
    #   canvas.text(0, 1, 'TTG CLUBHOUSE', :yellow)
    #   canvas.text(2, 1, '╭──╮', :light_blue)
    #   session.write_raw(canvas.frame)           # the whole screen, once
    #
    #   before = canvas.dup
    #   canvas.text(2, 2, '●', :red)
    #   session.write_raw(canvas.update(before))  # only the changed cell
    #
    # Byte sizes to aim for on a slow line: a whole screen of art about
    # 1.2 KB, one step of an animation under 200 bytes (#update picks the
    # cheaper of a patch and a frame).
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
        black: BLACK, white: WHITE, red: RED, cyan: CYAN, purple: PURPLE, green: GREEN, blue: BLUE,
        yellow: YELLOW, orange: ORANGE, brown: BROWN, light_red: LIGHT_RED, dark_grey: DARK_GREY,
        grey: GREY, light_green: LIGHT_GREEN, light_blue: LIGHT_BLUE, light_grey: LIGHT_GREY
      }.freeze

      # The sixteen colours as [red, green, blue] (the palette of VICE and
      # the C64 wiki, the one the boards match accents against), by code.
      RGB = {
        BLACK => [0, 0, 0], WHITE => [255, 255, 255], RED => [136, 0, 0], CYAN => [170, 255, 238],
        PURPLE => [204, 68, 204], GREEN => [0, 204, 85], BLUE => [0, 0, 170], YELLOW => [238, 238, 119],
        ORANGE => [221, 136, 85], BROWN => [102, 68, 0], LIGHT_RED => [255, 119, 119],
        DARK_GREY => [51, 51, 51], GREY => [119, 119, 119], LIGHT_GREEN => [170, 255, 102],
        LIGHT_BLUE => [0, 136, 255], LIGHT_GREY => [187, 187, 187]
      }.freeze

      # The graphics of the uppercase set by the Unicode character they look
      # like, as PETSCII codes: the shared BBS::Petscii::GRAPHICS and the
      # set's own BBS::Petscii::UPPERCASE_GRAPHICS.
      GLYPHS = Petscii::GRAPHICS.merge(Petscii::UPPERCASE_GRAPHICS).freeze
      # The graphics that are a code of GLYPHS in reverse video: the full
      # block a reversed space, the upper half a reversed lower half …
      GLYPHS_REVERSED = { '█' => 0x20, '▀' => 0xa2, '◢' => 0xa9, '◣' => 0xdf, '▐' => 0xa1 }.freeze
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

      # The character set the last #feed left the screen in: +:upper+ or
      # +:lower+.
      attr_reader :charset

      # Creates an empty screen: every cell a space with no colour.
      def initialize
        @cells   = Array.new(ROWS) { Array.new(COLS) { blank } }
        @at      = [0, 0]
        @pen     = nil
        @rvs     = false
        @charset = :upper
      end

      # The PETSCII code of +ch+ in the uppercase set, and whether it is a
      # reversed glyph (GLYPHS_REVERSED): <tt>[code, reversed]</tt>. A
      # character the set does not have is <tt>'?'</tt>.
      def self.code(ch)
        return [GLYPHS_REVERSED[ch], true] if GLYPHS_REVERSED.key?(ch)
        return [GLYPHS[ch], false] if GLYPHS.key?(ch)

        o = ch.upcase.ord
        o.between?(0x20, 0x5d) ? [o, false] : ['?'.ord, false]
      end

      # Whether the uppercase set shows +ch+ as what it is: a glyph of
      # GLYPHS or GLYPHS_REVERSED, or printable ASCII but the backslash (a
      # lowercase letter shows as its capital).
      def self.glyph?(ch)
        return true if GLYPHS.key?(ch) || GLYPHS_REVERSED.key?(ch)

        ch.length == 1 && ASCII_SHOWN.include?(ch.upcase.ord)
      end

      # The colour code of +color+: a code as it is (a key of RGB), an SGR
      # colour of the palette (BBS::Petscii::Colors), a name
      # of COLOR_NAMES as a Symbol or String (<tt>'light grey'</tt>,
      # <tt>:dark_gray</tt> and <tt>'LIGHT-BLUE'</tt> all work), or +nil+.
      # Raises ArgumentError for anything else.
      def self.color(color)
        return nil if color.nil?
        return color if color.is_a?(Integer) && RGB.key?(color)
        return Petscii.color_code(color) if color.to_s.start_with?(Ansi::ESC)

        name = color.to_s.downcase.tr(' -', '__').sub('gray', 'grey').to_sym
        COLOR_NAMES.fetch(name) { raise ArgumentError, "not a C64 colour: #{color.inspect}" }
      end

      # The code of the C64 colour nearest to +rgb+, [red, green, blue].
      def self.nearest(rgb) = RGB.min_by { |_, c| c.zip(rgb).sum { |a, b| (a - b)**2 } }.first

      # A copy with its own cells, to compare with after drawing (#update).
      def initialize_copy(source)
        super
        @cells = source.cells_copy
      end

      # Writes +text+ from +row+, +col+ (0-based) in +color+ (see ::color;
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

          code, reversed = Canvas.code(ch)
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

      # The whole screen: the graphics set, a clear screen, then the rows,
      # each cut after its last visible cell, as a binary String.
      def frame
        out = [UPPERCASE, CLEAR]
        state = { color: nil, rvs: false }
        last = ROWS - 1
        last -= 1 while last.positive? && visible_end(last).zero?
        (0..last).each do |row|
          len = visible_end(row)
          emit(out, @cells[row].first(len), state)
          next if len == COLS || row == last

          out << CR
          state[:rvs] = false
        end
        out.pack('C*')
      end

      # The cells of +row+ from +col+, +width+ long, with the cursor moves
      # that put them in place, as a binary String.
      def span(row, col, width)
        out = [HOME] + ([DOWN] * row) + ([RIGHT] * col)
        state = { color: nil, rvs: false }
        out << RVS_OFF
        emit(out, @cells[row][col, width], state)
        out << RVS_OFF if state[:rvs]
        out.pack('C*')
      end

      # The cells at +positions+, [row, col] each, the cursor stepping to the
      # nearest one left instead of from the top left each time: the cheap
      # repaint of a few cells scattered over the screen. A binary String.
      def patch(positions)
        out = [HOME, RVS_OFF]
        state = { color: nil, rvs: false }
        at = [0, 0]
        left = positions.uniq
        until left.empty?
          row, col = left.min_by { |r, c| [distance(at, r, c), r, c] }
          left.delete([row, col])
          if row + col < distance(at, row, col)
            out << HOME
            at = [0, 0]
          end
          out.concat(steps(at, row, col))
          emit(out, [@cells[row][col]], state)
          at = col == COLS - 1 ? [row + 1, 0] : [row, col + 1]
        end
        out << RVS_OFF if state[:rvs]
        out.pack('C*')
      end

      # The positions, [row, col] each, where this screen looks different
      # from +before+ (another Canvas): see Cell#looks_like?.
      def changes(before)
        (0...ROWS).flat_map do |row|
          (0...COLS).filter_map { |col| [row, col] unless @cells[row][col].looks_like?(before.cell(row, col)) }
        end
      end

      # The bytes that turn +before+ (another Canvas, what the caller sees)
      # into this screen: a #patch of the #changes, or the whole #frame when
      # that is shorter; an empty String when nothing changed.
      def update(before)
        changed = changes(before)
        return ''.b if changed.empty?

        cheap = patch(changed)
        whole = frame
        cheap.bytesize <= whole.bytesize ? cheap : whole
      end

      # The cursor moves to +row+, +col+, with nothing printed: HOME, then
      # down and right. A binary String.
      def cursor(row, col) = ([HOME] + ([DOWN] * row) + ([RIGHT] * col)).pack('C*')

      # Plays +bytes+ (PETSCII, a String) onto the screen the way the C64's
      # screen editor prints them: colours, reverse video, CLR, HOME, the
      # cursor keys, RETURN, the character set switches and printable codes;
      # the cursor wraps at the end of a row and the screen scrolls at the
      # bottom. Other codes are skipped. The cursor, colour and reverse state
      # carry over to the next call. For tests and previews: what a C64 shows
      # after a #frame, #span or #patch.
      #
      # Returns +self+.
      def feed(bytes)
        bytes.to_s.each_byte { |b| play(b) }
        self
      end

      # The screen as text, a line a row, each cell the Unicode character it
      # looks like (a reversed cell as it is printed, not inverted); for
      # tests and logs.
      def to_s
        looks = GLYPHS.invert
        @cells.map { |row| row.map { |c| looks[c.code] || (c.code < 0x80 ? c.code.chr : '?') }.join.rstrip }.join("\n")
      end

      protected

      # A deep copy of the rows of cells.
      def cells_copy = @cells.map { |row| row.map(&:dup) }

      private

      def blank = Cell.new(SPACE, nil, false)

      def distance(from, row, col) = (row - from[0]).abs + (col - from[1]).abs

      def steps(from, row, col)
        dr = row - from[0]
        dc = col - from[1]
        (dr.negative? ? [UP] * -dr : [DOWN] * dr) + (dc.negative? ? [LEFT] * -dc : [RIGHT] * dc)
      end

      def inside?(row, col) = row.between?(0, ROWS - 1) && col.between?(0, COLS - 1) && !(row == ROWS - 1 && col == COLS - 1)

      def visible_end(row)
        cells = @cells[row]
        len = cells.size
        len -= 1 while len.positive? && cells[len - 1].code == SPACE && !cells[len - 1].rvs
        len
      end

      def emit(out, cells, state)
        cells.each do |cell|
          visible = cell.code != SPACE || cell.rvs
          if visible && cell.color && cell.color != state[:color]
            out << cell.color
            state[:color] = cell.color
          end
          if cell.rvs != state[:rvs] && (visible || state[:rvs])
            out << (cell.rvs ? RVS_ON : RVS_OFF)
            state[:rvs] = cell.rvs
          end
          out << cell.code
        end
      end

      # One byte of #feed.
      def play(byte)
        return @pen = byte if RGB.key?(byte)

        case byte
        when CLEAR then wipe
        when HOME then @at = [0, 0]
        when RVS_ON then @rvs = true
        when RVS_OFF then @rvs = false
        when CR then newline
        when UPPERCASE then @charset = :upper
        when LOWERCASE then @charset = :lower
        when DOWN then @at[0] == ROWS - 1 ? scroll : @at[0] += 1
        when UP then @at[0] -= 1 if @at[0].positive?
        when RIGHT then advance
        when LEFT then back
        when 0x20..0x7f, 0xa0..0xff then print_code(byte)
        end
      end

      def wipe
        @cells = Array.new(ROWS) { Array.new(COLS) { blank } }
        @at = [0, 0]
      end

      def newline
        @rvs = false
        @at[1] = 0
        @at[0] == ROWS - 1 ? scroll : @at[0] += 1
      end

      def print_code(byte)
        @cells[@at[0]][@at[1]] = Cell.new(byte, @pen, @rvs)
        advance
      end

      def advance
        @at[1] += 1
        return if @at[1] < COLS

        @at[1] = 0
        @at[0] == ROWS - 1 ? scroll : @at[0] += 1
      end

      def back
        if @at[1].positive?
          @at[1] -= 1
        elsif @at[0].positive?
          @at = [@at[0] - 1, COLS - 1]
        end
      end

      def scroll
        @cells.shift
        @cells << Array.new(COLS) { blank }
      end
    end
  end
end
