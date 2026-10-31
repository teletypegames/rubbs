# frozen_string_literal: true

module BBS
  # A menu at the cursor for a line-by-line board, on a Commodore 64 and a
  # modern terminal alike: the items one under the other (in one column or
  # several, or side by side on one row), the chosen one lit as a reversed
  # bar that the cursor keys move. RETURN takes the lit item; an item's own
  # key (a letter or a digit) takes it at once, so a caller who knows the
  # menu types as before. With +numbers+ the items are numbered instead, and
  # the digits typed light the item of that number. More items than a page
  # holds turn into pages.
  #
  # Like BBS::Field it draws from where the cursor is (at the start of a
  # line) downwards and moves with a BBS::Cursor, so a C64 never gets HOME;
  # after the choice the cursor is on the line under the menu.
  #
  # Under the items it can show two more rows: the lit item's +about+, when
  # an item has one, and a status row with the +hint+, the number being
  # typed and the page.
  #
  # Keys:
  #
  # [cursor up, down]      the item before, after (down a column, then on
  #                        to the next one and across the pages)
  # [cursor left, right]   on one row the item before, after; in columns
  #                        the item beside it; otherwise the page before,
  #                        after
  # [+, -, PgUp, PgDn]     the page before, after
  # [HOME, END]            the first, the last item
  # [RETURN]               takes the lit item
  # [an item's key]        takes that item
  # [digits]               with +numbers+: lights the item of that number
  # [RUN/STOP, ←, Esc]     returns +back+
  #
  #   items = [BBS::Selector.item('latest posts', key: 'l', value: :latest),
  #            BBS::Selector.item('log off', key: 'q', value: :quit)]
  #   case BBS::Selector.new(session, items, width: 38).run
  #   when :latest then latest
  #   when :quit, nil then return
  #   end
  class Selector
    # One cell of the menu: its +label+ (ANSI colours allowed), its +key+
    # (a letter or digit that takes it, or +nil+), its +value+ (what #run
    # returns for it), its +about+ (a line shown under the menu while it is
    # lit, or +nil+), its +color+ (an SGR sequence for its key and its bar
    # in place of the menu's, or +nil+) and +heading+ (true for a cell that
    # only labels the ones under it, or keeps a place empty, and is never
    # lit).
    Item = Struct.new(:label, :key, :value, :about, :color, :heading, keyword_init: true) do
      # Whether the cursor can light it: every cell but a heading.
      def selectable? = !heading
    end

    # The colours as ANSI SGR sequences: +text+ the labels, +key+ the keys
    # and numbers, +bar+ the lit cell (reversed), +heading+ the headings,
    # +about+ the about row, +hint+ the status row.
    COLORS = {
      text: "\e[0;37m", key: "\e[1;33m", bar: "\e[0;36m", heading: "\e[1;30m",
      about: "\e[2;37m", hint: "\e[1;30m"
    }.freeze
    # The keys that return +back+.
    BACK_KEYS = %i[escape interrupt].freeze
    # The keys that turn the page, and which way.
    PAGE_KEYS = { page_up: -1, page_down: 1, '-' => -1, '+' => 1 }.freeze
    # The keys that go sideways, and which way.
    SIDE_KEYS = { left: -1, right: 1 }.freeze
    # The most digits a number typed with +numbers+ can have.
    MAX_DIGITS = 4

    # An Item that can be lit: +label+, and the +key+ that takes it, the
    # +value+ #run returns for it, its +about+ line and its +color+.
    def self.item(label, key: nil, value: nil, about: nil, color: nil)
      Item.new(label: label, key: key, value: value, about: about, color: color)
    end

    # A heading Item: +label+ (ANSI colours allowed) shown in the heading
    # colour, never lit. An empty label keeps a place empty.
    def self.heading(label = '') = Item.new(label: label, heading: true)

    # A numbered menu of +objects+, each labelled by the block; the object
    # taken, or +back+. The other options are those of ::new.
    #
    #   post = BBS::Selector.list(session, posts, width: 38, height: 18, &:title)
    def self.list(session, objects, back: nil, **options, &label)
      items = objects.map { |o| item(label.call(o).to_s, value: o) }
      new(session, items, numbers: true, back: back, **options).run
    end

    # The index of the lit item in the items; after #run, the one taken.
    attr_reader :index

    # Creates a menu for +session+.
    #
    # [items]   the cells, an Array of Item (see ::item and ::heading),
    #           down the first column, then down the next; at least one
    #           must be selectable
    # [width]   the columns the menu takes; on a C64 keep it out of the last
    #           column
    # [height]  the rows a page shows; default all the items, shared out
    #           among the +columns+
    # [columns] the columns of cells side by side, each as wide as the
    #           +width+ shared out
    # [index]   the item lit first; default the first selectable one
    # [numbers] true to number the items (1, 2, …) and let the digits
    #           typed light them; the items' own keys still work
    # [across]  true to put the items side by side on one row
    # [hint]    a line for the status row, or +nil+
    # [exits]   more keys and what #run returns for them, e.g.
    #           <tt>{ 'q' => :quit }</tt>
    # [back]    what #run returns for RUN/STOP, ← or Esc
    # [colors]  colours over COLORS
    def initialize(session, items, width:, height: nil, columns: 1, index: nil, numbers: false, across: false,
                   hint: nil, exits: {}, back: nil, colors: {})
      raise ArgumentError, 'a selector needs an item to select' unless items.any?(&:selectable?)

      @session = session
      @items   = items
      @width   = [width, 4].max
      @columns = across ? 1 : columns.clamp(1, items.size)
      @height  = across ? items.size : (height || ((items.size + @columns - 1) / @columns)).clamp(1, items.size)
      @numbers = numbers
      @across  = across
      @hint    = hint
      @exits   = exits.transform_keys { |k| k.is_a?(String) ? k.downcase : k }
      @back    = back
      @colors  = COLORS.merge(colors)
      @index   = index && items[index]&.selectable? ? index : step(-1, 1)
      @typed   = +''
      @about   = items.any?(&:about) ? 1 : 0
      @status  = numbers || hint || pages > 1 ? 1 : 0
    end

    # Draws the menu, then reads keys until an item is taken or the caller
    # goes back; the cursor ends on the line under the menu.
    #
    # Returns the taken item's +value+, an +exits+ value, or +back+. Raises
    # IOError when the caller hangs up.
    def run
      draw
      loop do
        key = @screen.key
        return finish(@back) if BACK_KEYS.include?(key)
        return finish(@items[@index].value) if key == :enter

        if (item = hotkey(key))
          light(@items.index(item))
          return finish(item.value)
        end
        return finish(@exits[fold(key)]) if @exits.key?(fold(key))

        react(key)
      end
    end

    private

    def per_page = @height * @columns

    def pages = (@items.size + per_page - 1) / per_page

    def page = @index / per_page

    # The screen row of item +index+ in the menu, from 1.
    def line_of(index) = @across ? 1 : (index % per_page % @height) + 1

    def rows = (@across ? 1 : @height) + @about + @status

    def fold(key) = key.is_a?(String) ? key.downcase : key

    def hotkey(key)
      return nil unless key.is_a?(String) && key.length == 1
      return nil if @numbers && key.match?(/\d/)

      @items.find { |i| i.selectable? && i.key && i.key.to_s.downcase == key.downcase }
    end

    def react(key)
      case key
      when :up then move(-1)
      when :down then move(1)
      when :home then light(step(-1, 1))
      when :end then light(step(@items.size, -1))
      when :backspace then type(@typed.chop)
      when *SIDE_KEYS.keys then side(SIDE_KEYS[key])
      when *PAGE_KEYS.keys then turn(PAGE_KEYS[key])
      else
        type(@typed + key) if @numbers && key.is_a?(String) && key.match?(/\A\d\z/)
      end
    end

    # The next selectable item from +from+ in direction +dir+, round the end.
    def step(from, dir)
      (1..@items.size).each do |n|
        i = (from + (dir * n)) % @items.size
        return i if @items[i].selectable?
      end
    end

    def move(dir)
      @typed.clear
      light(step(@index, dir))
    end

    # Sideways: the next item on one row, the item beside in columns (the
    # nearest selectable one under it, else above it), else the page.
    def side(dir)
      return move(dir) if @across
      return turn(dir) if @columns == 1

      target = @index + (dir * @height)
      return turn(dir) unless target.between?(0, @items.size - 1) && target / per_page == page

      top    = target - (target % per_page % @height)
      column = (top...[top + @height, @items.size].min).select { |i| @items[i].selectable? }
      return if column.empty?

      @typed.clear
      light(column.min_by { |i| [(i - target).abs, i < target ? 1 : 0] })
    end

    def turn(dir)
      return if pages == 1

      @typed.clear
      first = ((page + dir) % pages) * per_page
      light(@items[first].selectable? ? first : step(first, 1))
    end

    # The digits typed so far as +digits+: the item of that number lit when
    # there is one; a digit that would make no item's number is dropped.
    def type(digits)
      return if digits.length > MAX_DIGITS
      return if !digits.empty? && !digits.to_i.between?(1, @items.size)

      @typed = digits
      @typed.empty? ? paint_status : light(@typed.to_i - 1)
    end

    # Lights item +index+, repainting what changed: the rows of the old and
    # the new item, or the whole page when the page turned.
    def light(index)
      old    = @index
      turned = index / per_page != page
      @index = index
      lines  = turned ? (1..@height).to_a : [line_of(old), line_of(index)].uniq
      out = +''
      lines.each { |l| out << row_at(l, line(l)) }
      out << about_row << status_row << park
      @session.write(out)
    end

    def paint_status = @session.write(status_row << park)

    def draw
      lines = Array.new(@across ? 1 : @height) { |l| line(l + 1) }
      lines << about_text if @about.positive?
      lines << status_text if @status.positive?
      @session.write(lines.join(Ansi::CRLF))
      @screen = Cursor.new(@session, row: lines.size, col: @width + 1)
      @session.write(park)
    end

    # The cursor to the start of the lit item.
    def park
      col = @across ? 1 : 1 + (cell_width * (@index % per_page / @height))
      @screen.move(line_of(@index), col)
    end

    def finish(result)
      @session.write(@screen.move(rows, 1) << Ansi::CRLF)
      result
    end

    # The bytes that write +text+ (exactly +@width+ columns) on row +row+.
    def row_at(row, text)
      out = @screen.move(row, 1) << text
      @screen.wrote(@width)
      out
    end

    def about_row = @about.positive? ? row_at((@across ? 1 : @height) + 1, about_text) : +''

    def status_row = @status.positive? ? row_at(rows, status_text) : +''

    def cell_width = @width / @columns

    # Screen row +number+ of the page: the cell of each column side by side,
    # the last column taking what the others leave.
    def line(number)
      return across_row if @across

      first = (page * per_page) + number - 1
      (0...@columns).map do |c|
        width = c == @columns - 1 ? @width - (cell_width * c) : cell_width
        cell(first + (c * @height), width)
      end.join
    end

    def key_width
      @key_width ||= if @numbers
                       @items.size.to_s.length
                     else
                       @items.map { |i| i.key.to_s.length }.max
                     end
    end

    def key_text(index)
      key = @numbers ? (index + 1).to_s : @items[index].key.to_s.upcase
      key.rjust(key_width)
    end

    # Item +index+ as a cell +width+ wide: blank past the last item, a
    # heading in its colour, the lit one as a bar of plain text (an SGR
    # reset inside it would end the reversing), the others in their own
    # colours.
    def cell(index, width)
      item = @items[index]
      return "#{@colors[:text]}#{' ' * width}" unless item
      return "#{@colors[:heading]}#{fit_ansi(" #{item.label}", width)}#{@colors[:text]}" if item.heading

      prefix = key_width.positive? ? " #{key_text(index)} " : ' '
      if index == @index
        bar = item.color || @colors[:bar]
        "#{bar}#{Ansi::REVERSE}#{fit(prefix + plain(item.label), width)}#{Ansi::REVERSE_OFF}#{@colors[:text]}"
      else
        key = item.color || @colors[:key]
        "#{key}#{prefix}#{@colors[:text]}#{fit_ansi(item.label.to_s, width - prefix.length)}#{@colors[:text]}"
      end
    end

    # The items on one row, each a key letter and its label, the lit one a
    # bar; the items that do not fit are left off.
    def across_row
      out  = +''
      used = 0
      @items.each_with_index do |item, i|
        word = item.key ? "#{item.key.to_s.upcase} #{plain(item.label)}" : plain(item.label)
        break if used + word.length + 2 > @width

        out << if i == @index
                 "#{item.color || @colors[:bar]}#{Ansi::REVERSE} #{word} #{Ansi::REVERSE_OFF}#{@colors[:text]}"
               elsif item.key
                 " #{item.color || @colors[:key]}#{item.key.to_s.upcase}#{@colors[:text]} #{plain(item.label)} "
               else
                 " #{@colors[:text]}#{word} "
               end
        used += word.length + 2
      end
      "#{@colors[:text]}#{out}#{' ' * (@width - used)}"
    end

    def about_text = "#{@colors[:about]}#{fit(" #{plain(@items[@index].about)}", @width)}#{@colors[:text]}"

    def status_text
      right = if !@typed.empty? then "##{@typed}"
              elsif pages > 1 then "#{page + 1}/#{pages}"
              else ''
              end
      left = " #{@hint}"[0, [@width - right.length - 1, 0].max]
      "#{@colors[:hint]}#{left}#{' ' * (@width - left.length - right.length)}#{right}#{@colors[:text]}"
    end

    def plain(text) = FrameBuffer.text(text.to_s).gsub(FrameBuffer::ANSI_ESC_RE, '')

    def fit(text, width) = text.length > width ? text[0, width] : text.ljust(width)

    # +text+ with its colours cut or padded to +width+ visible columns.
    def fit_ansi(text, width)
      text = FrameBuffer.clip_ansi(text, width)
      "#{text}#{' ' * (width - FrameBuffer.visible_width(text))}"
    end
  end
end
