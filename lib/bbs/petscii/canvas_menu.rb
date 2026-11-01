# frozen_string_literal: true

module BBS
  module Petscii
    # A BBS::Selector drawn on a BBS::Petscii::Canvas: the cursor menu of a
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
    # BBS::Petscii::Canvas code or name (+:yellow+).
    #
    #   canvas = BBS::Petscii::Canvas.new
    #   house.draw_canvas(canvas)                      # a BBS::Art
    #   items = [BBS::Selector.item('CORK BOARD', key: 'm', value: :boards, color: :light_blue),
    #            BBS::Selector.item('GAMES ROOM', key: 'r', value: :doors, color: :orange),
    #            BBS::Selector.item('LEAVE', key: 'q', value: :quit)]
    #   menu = BBS::Petscii::CanvasMenu.new(session, items, canvas: canvas, row: 12, col: 1,
    #                                       width: 36, columns: 2, hint: 'CRSR: CHOOSE  RETURN: OPEN')
    #   menu.paint
    #   session.write_raw(canvas.frame)
    #   choice = menu.run(drawn: true)
    #
    # With +idle+ seconds and a block the menu animates while the caller
    # thinks: the block is called each time +idle+ seconds pass without a
    # key and returns the bytes to send (or +nil+); a key stops waiting at
    # once.
    class CanvasMenu < Selector
      # The colours, C64 colour codes: +text+ the labels, +key+ the keys and
      # numbers, +bar+ the lit cell (reversed), +heading+ the headings,
      # +about+ the about row, +hint+ the status row.
      COLORS = {
        text: Canvas::LIGHT_GREY, key: Canvas::YELLOW, bar: Canvas::CYAN, heading: Canvas::DARK_GREY,
        about: Canvas::GREY, hint: Canvas::DARK_GREY
      }.freeze

      # The canvas the menu is drawn on.
      attr_reader :canvas

      # Creates a menu for +session+ on +canvas+.
      #
      # [items]  the cells, Selector::Item (BBS::Selector.item and
      #          BBS::Selector.heading); an item's +color+ is a C64 colour
      # [canvas] the BBS::Petscii::Canvas of the screen
      # [row]    the screen row of the first item, 0-based
      # [col]    the screen column of the menu's left edge, 0-based
      # [rest]   where the cursor waits after each change, [row, col];
      #          default the start of the screen's last row
      # [idle]   seconds without a key after which the block is called,
      #          or +nil+
      # [colors] colours over COLORS (C64 codes or names)
      #
      # The other options (+width+, +height+, +columns+, +index+,
      # +numbers+, +across+, +hint+, +exits+, +back+) are those of
      # BBS::Selector.new. Raises ArgumentError for a menu with nothing to
      # select or an unknown colour.
      def initialize(session, items, canvas:, row:, col:, width:, rest: [Canvas::ROWS - 1, 0], idle: nil,
                     colors: {}, **options, &on_idle)
        super(session, items, width: width, **options)
        @canvas  = canvas
        @top     = row
        @left    = col
        @rest    = rest
        @idle    = idle
        @on_idle = on_idle
        @colors  = COLORS.merge(colors.transform_values { |c| Canvas.color(c) })
      end

      # Draws the whole menu onto the canvas, sending nothing. Returns
      # +self+.
      def paint
        (1..rows).each { |l| paint_line(l) }
        self
      end

      # Reads keys until an item is taken or the caller goes back, as
      # BBS::Selector#run does. With +drawn+ the caller has already sent
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
          @idle    = idle
          @on_idle = on_idle
        end

        # The next key; the bytes +on_idle+ returns go out raw meanwhile.
        # Raises IOError when the caller hangs up.
        def key
          loop do
            k = @idle && @on_idle ? @session.readkey(timeout: @idle) : @session.readkey
            raise IOError, 'the caller hung up' if k.nil?
            return k unless k == :idle && @idle && @on_idle

            out = @on_idle.call
            @session.write_raw(out) if out && !out.empty?
          end
        end
      end

      private_constant :Keys

      def draw
        @screen = Keys.new(@session, @idle, @on_idle)
        return if @drawn

        paint
        send_lines((1..rows).to_a)
      end

      def light(index)
        old    = @index
        turned = index / per_page != page
        @index = index
        lines  = turned ? (1..(@across ? 1 : @height)).to_a : [line_of(old), line_of(index)].uniq
        lines << ((@across ? 1 : @height) + 1) if @about.positive?
        lines << rows if @status.positive?
        repaint(lines.uniq)
      end

      def paint_status
        repaint([rows]) if @status.positive?
      end

      # Paints menu lines +lines+ and sends what changed in them: the
      # changed cells as a patch, or the lines' spans when that is shorter.
      def repaint(lines)
        before = @canvas.dup
        lines.each { |l| paint_line(l) }
        rows = screen_rows(lines)
        cells = @canvas.changes(before).select { |r, _| rows.include?(r) }
        return @session.write_raw(@canvas.cursor(*@rest)) if cells.empty?

        patch = @canvas.patch(cells)
        spans = rows.map { |r| @canvas.span(r, @left, @width) }.join.b
        @session.write_raw((patch.bytesize < spans.bytesize ? patch : spans) + @canvas.cursor(*@rest))
      end

      def finish(result) = result

      # The screen rows of menu lines +lines+ that are on the screen.
      def screen_rows(lines) = lines.map { |l| @top + l - 1 }.select { |r| r.between?(0, Canvas::ROWS - 1) }

      # The spans of menu lines +lines+ and the cursor to +rest+.
      def send_lines(lines)
        out = screen_rows(lines).map { |r| @canvas.span(r, @left, @width) }.join.b
        @session.write_raw(out + @canvas.cursor(*@rest))
      end

      # Paints menu line +number+ (1-based: the items' rows, then the
      # about row, then the status row) onto the canvas.
      def paint_line(number)
        item_rows = @across ? 1 : @height
        segments = if number <= item_rows then segments_of(number)
                   elsif @about.positive? && number == item_rows + 1 then about_segments
                   else status_segments
                   end
        row = @top + number - 1
        @canvas.clear(row, @left, @width)
        col = @left
        segments.each do |text, color, rvs|
          @canvas.text(row, col, text, color, rvs: rvs)
          col += text.length
        end
      end

      def segments_of(number)
        return across_segments if @across

        first = (page * per_page) + number - 1
        (0...@columns).flat_map do |c|
          width = c == @columns - 1 ? @width - (cell_width * c) : cell_width
          cell_segments(first + (c * @height), width)
        end
      end

      def cell_segments(index, width)
        item = @items[index]
        return [[' ' * width, @colors[:text], false]] unless item
        return [[fit(" #{plain(item.label)}", width), @colors[:heading], false]] if item.heading

        prefix = key_width.positive? ? " #{key_text(index)} " : ' '
        color  = item.color && Canvas.color(item.color)
        return [[fit(prefix + plain(item.label), width), color || @colors[:bar], true]] if index == @index

        [[prefix, color || @colors[:key], false],
         [fit(plain(item.label), [width - prefix.length, 0].max), @colors[:text], false]]
      end

      # The items on one row: a key letter and a label each, the lit one a
      # bar; the items that do not fit are left off.
      def across_segments
        out  = []
        used = 0
        @items.each_with_index do |item, i|
          word = item.key ? "#{item.key.to_s.upcase} #{plain(item.label)}" : plain(item.label)
          break if used + word.length + 2 > @width

          color = item.color && Canvas.color(item.color)
          if i == @index
            out << [" #{word} ", color || @colors[:bar], true]
          elsif item.key
            out << [' ', @colors[:text], false] << [item.key.to_s.upcase, color || @colors[:key], false]
            out << [" #{plain(item.label)} ", @colors[:text], false]
          else
            out << [" #{word} ", @colors[:text], false]
          end
          used += word.length + 2
        end
        out
      end

      def about_segments = [[fit(" #{plain(@items[@index].about)}", @width), @colors[:about], false]]

      def status_segments
        right = if !@typed.empty? then "##{@typed}"
                elsif pages > 1 then "#{page + 1}/#{pages}"
                else ''
                end
        left = " #{plain(@hint.to_s)}"[0, [@width - right.length - 1, 0].max]
        [[left + (' ' * (@width - left.length - right.length)) + right, @colors[:hint], false]]
      end

      # +text+ without colours, in characters the C64 shows.
      def plain(text) = Petscii.plain(super)
    end
  end
end
