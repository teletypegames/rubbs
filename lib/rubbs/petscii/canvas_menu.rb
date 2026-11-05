# frozen_string_literal: true

module Rubbs
  module Petscii
    # A Rubbs::Common::Screens::Selector drawn on a Rubbs::Petscii::Canvas: the cursor menu of a
    # graphics screen of a C64 board, in the uppercase/graphics set. The
    # keys and the items are the Selector's (CRSR, RETURN, an item's key,
    # RUN/STOP or ← for +back+, numbers, columns, pages, the about and
    # status rows); only the drawing differs: the lit item is a reversed
    # bar in its own colour, and each change goes out as raw PETSCII, the
    # spans of the rows that changed, through <tt>session.write_raw</tt>.
    #
    # The menu takes the rectangle at +row+, +col+ (0-based), +width+
    # columns wide, of the canvas the board draws its screen on. Either the
    # board draws the whole screen first (#paint the menu onto the canvas,
    # send the canvas's +frame+, then <tt>run(drawn: true)</tt>), or #run
    # paints the menu and sends its rows itself.
    #
    # The colours (+colors+ and an Item's +color+) are C64 colours: a
    # Rubbs::Petscii::Canvas code, a name (+:yellow+) or a colour of the
    # palette (Rubbs::Petscii::Colors, +YE+); the roles default to the
    # Selector's COLORS.
    #
    #   canvas = Rubbs::Petscii::Canvas.new
    #   house.draw_canvas(canvas)                      # a Rubbs::Common::Art
    #   items = [Rubbs::Common::Screens::Selector.item('CORK BOARD', key: 'm', value: :boards, color: :light_blue),
    #            Rubbs::Common::Screens::Selector.item('GAMES ROOM', key: 'r', value: :doors, color: :orange),
    #            Rubbs::Common::Screens::Selector.item('LEAVE', key: 'q', value: :quit)]
    #   menu = Rubbs::Petscii::CanvasMenu.new(session, items, canvas: canvas, row: 12, col: 1,
    #                                       width: 36, columns: 2, hint: 'CRSR: CHOOSE  RETURN: OPEN')
    #   menu.paint
    #   session.write_raw(canvas.frame)
    #   choice = menu.run(drawn: true)
    #
    # With +idle+ seconds and a block the menu animates while the caller
    # thinks: the block is called each time +idle+ seconds pass without a
    # key and returns the bytes to send (or +nil+); a key stops waiting at
    # once.
    class CanvasMenu < Common::Screens::Selector
      # The canvas the menu is drawn on.
      attr_reader :canvas

      # Creates a menu for +session+ on +canvas+.
      #
      # [items]  the cells, Selector::Item (Rubbs::Common::Screens::Selector.item and
      #          Rubbs::Common::Screens::Selector.heading); an item's +color+ is a C64 colour
      # [canvas] the Rubbs::Petscii::Canvas of the screen
      # [row]    the screen row of the first item, 0-based
      # [col]    the screen column of the menu's left edge, 0-based
      # [rest]   where the cursor waits after each change, [row, col];
      #          default the start of the screen's last row
      # [idle]   seconds without a key after which the block is called,
      #          or +nil+
      #
      # The other options (+width+, +height+, +columns+, +index+,
      # +numbers+, +across+, +hint+, +exits+, +item_exits+, +back+,
      # +colors+) are those of
      # Rubbs::Common::Screens::Selector.new. Raises ArgumentError for a menu with nothing to
      # select or an unknown colour.
      def initialize(session, items, canvas:, row:, col:, rest: [Canvas::ROWS - 1, 0], idle: nil, **, &on_idle)
        super(session, items, **)
        @canvas  = canvas
        @top     = row
        @left    = col
        @rest    = rest
        @keys    = Keys.new(session, idle, on_idle)
        @colors  = @colors.transform_values { |c| Canvas.color(c) }
      end

      # Draws the whole menu onto the canvas, sending nothing. Returns
      # +self+.
      def paint
        (1..rows).each { |l| paint_line(l) }
        self
      end

      # Reads keys until an item is taken or the caller goes back, as
      # Rubbs::Common::Screens::Selector#run does. With +drawn+ the caller has already sent
      # the screen with the menu #paint ed on it; otherwise the menu paints
      # itself and sends its rows first.
      #
      # Returns the taken item's +value+, an +exits+ value, or +back+.
      # Raises IOError when the caller hangs up.
      def run(drawn: false)
        @drawn = drawn
        super()
      end

      private

      # The keys of the session; while waiting, the idle block every +idle+
      # seconds.
      class Keys
        # Reads the keys of +session+, calling +on_idle+ every +idle+
        # seconds without one (when both are given).
        def initialize(session, idle, on_idle)
          @session = session
          @idle    = idle && on_idle ? idle : nil
          @on_idle = on_idle
        end

        # The next key; the bytes +on_idle+ returns go out raw meanwhile.
        # Raises IOError when the caller hangs up.
        def key
          loop do
            k = @session.readkey(timeout: @idle)
            raise IOError, 'the caller hung up' if k.nil?
            return k unless k == :idle && @idle

            out = @on_idle.call
            @session.write_raw(out) if out && !out.empty?
          end
        end
      end

      private_constant :Keys

      def read_key = @keys.key

      def draw
        return if @drawn

        paint
        send_rows(spans(screen_rows((1..rows).to_a)))
      end

      # Paints menu lines +lines+ and sends what changed in them: the
      # changed cells as a patch, or the lines' spans when that is shorter.
      def repaint(lines)
        before = @canvas.dup
        lines.each { |l| paint_line(l) }
        rows  = screen_rows(lines)
        cells = @canvas.changes(before).select { |position| rows.include?(position.first) }
        send_rows(cells.empty? ? ''.b : [@canvas.patch(cells), spans(rows)].min_by(&:bytesize))
      end

      # The spans of screen rows +rows+, the menu's width each.
      def spans(rows) = rows.map { |r| @canvas.span(r, @left, @width) }.join.b

      def finish(result) = result

      # +bytes+ and the cursor to +rest+, raw.
      def send_rows(bytes) = @session.write_raw(bytes + @canvas.cursor(*@rest))

      # The screen rows of menu lines +lines+ that are on the screen.
      def screen_rows(lines) = lines.map { |l| @top + l - 1 }.grep(0..(Canvas::ROWS - 1))

      # Paints the segments of menu line +number+ onto the canvas.
      def paint_line(number)
        row = @top + number - 1
        @canvas.clear(row, @left, @width)
        line_segments(number).reduce(@left) do |col, (text, color, reversed)|
          @canvas.text(row, col, text, color.is_a?(Symbol) ? @colors[color] : color, rvs: reversed || false)
          col + text.length
        end
      end

      # +text+ without colours, in characters the C64 shows.
      def plain(text) = Petscii.plain(super)

      # A label made #plain, cut or padded to +width+.
      def label(text, width) = fit(plain(text), width)
    end
  end
end
