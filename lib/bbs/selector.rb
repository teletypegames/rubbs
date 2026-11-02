# frozen_string_literal: true

require_relative 'petscii'
require_relative 'petscii/colors'

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
    # lit, or +nil+), its +color+ (a colour for its key and its bar in place
    # of the menu's, or +nil+) and +heading+ (true for a cell that only
    # labels the ones under it, or keeps a place empty, and is never lit).
    Item = Struct.new(:label, :key, :value, :about, :color, :heading, keyword_init: true) do
      # Whether the cursor can light it: every cell but a heading.
      def selectable? = !heading
    end

    # The colours of the roles, from the C64 palette (BBS::Petscii::Colors):
    # +text+ the labels, +key+ the keys and numbers, +bar+ the lit cell
    # (reversed), +heading+ the headings, +about+ the about row, +hint+ the
    # status row.
    COLORS = {
      text: Petscii::Colors::LG, key: Petscii::Colors::YE, bar: Petscii::Colors::CY,
      heading: Petscii::Colors::DG, about: Petscii::Colors::GR, hint: Petscii::Colors::DG
    }.freeze
    # The keys that return +back+.
    BACK_KEYS = %i[escape interrupt].freeze
    # The keys that turn the page, and which way.
    PAGE_KEYS = { page_up: -1, page_down: 1, '-' => -1, '+' => 1 }.freeze
    # The keys that go sideways, and which way.
    SIDE_KEYS = { left: -1, right: 1 }.freeze
    # The keys that go up and down, and which way.
    STEP_KEYS = { up: -1, down: 1 }.freeze
    # The most digits a number typed with +numbers+ can have.
    MAX_DIGITS = 4
    # One digit typed.
    DIGIT = /\A\d\z/

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
    def self.list(session, objects, back: nil, **, &label)
      items = objects.map { |o| item(label.call(o).to_s, value: o) }
      new(session, items, numbers: true, back: back, **).run
    end

    # The index of the lit item in the items; after #run, the one taken.
    attr_reader :index
    # The columns the menu takes.
    attr_reader :width

    # Creates a menu for +session+.
    #
    # [items]   the cells, an Array of Item (see ::item and ::heading),
    #           down the first column, then down the next; at least one
    #           must be selectable
    # [width]   the columns the menu takes; on a C64 keep it out of the last
    #           column
    # [height]  the rows a page shows; default all the items, shared out
    #           among the +columns+
    # [fill]    true to keep +height+ rows even when the items take fewer:
    #           the rows under the last item stay blank, so the about and
    #           status rows stand where a full page puts them
    # [columns] the columns of cells side by side, each as wide as the
    #           +width+ shared out
    # [across]  true to put the items side by side on one row (a Row
    #           layout instead of Columns)
    # [index]   the item lit first; default the first selectable one
    # [numbers] true to number the items (1, 2, …) and let the digits
    #           typed light them; the items' own keys still work
    # [hint]    a line for the status row, or +nil+
    # [exits]   more keys and what #run returns for them, e.g.
    #           <tt>{ 'q' => :quit }</tt>
    # [back]    what #run returns for RUN/STOP, ← or Esc
    # [colors]  colours of the roles over COLORS
    #
    # Raises ArgumentError when no item can be selected.
    def initialize(session, items, width:, height: nil, columns: 1, index: nil, numbers: false, across: false,
                   hint: nil, exits: {}, back: nil, colors: {}, fill: false)
      raise ArgumentError, 'a selector needs an item to select' unless items.any?(&:selectable?)

      @session = session
      @items   = items
      @width   = [width, 4].max
      @layout  = across ? Row.new(items.size) : Columns.new(items.size, height: height, columns: columns, fill: fill)
      @numbers = numbers
      @hint    = hint
      @exits   = exits.transform_keys { |k| fold(k) }
      @back    = back
      @colors  = self.class::COLORS.merge(colors)
      @index   = index && items[index]&.selectable? ? index : step(-1, 1)
      @typed   = +''
    end

    # Draws the menu, then reads keys until an item is taken or the caller
    # goes back; the cursor ends on the line under the menu.
    #
    # Returns the taken item's +value+, an +exits+ value, or +back+. Raises
    # IOError when the caller hangs up.
    def run
      draw
      loop do
        key = read_key
        result = take(key)
        return finish(result.first) if result

        react(key)
      end
    end

    # The page shown, from 0.
    def page = @layout.page_of(@index)

    # Whether item +index+ can be lit.
    def selectable?(index) = @items[index].selectable?

    # Lights the next selectable item in direction +dir+ (1 or -1).
    def move(dir) = jump(step(@index, dir))

    # Lights item +index+, forgetting the digits typed.
    def jump(index)
      @typed.clear
      light(index)
    end

    # Turns to the page beside, +dir+ (1 or -1), lighting its first
    # selectable item.
    def turn(dir)
      return if pages == 1

      first = ((page + dir) % pages) * per_page
      jump(@items[first].selectable? ? first : step(first, 1))
    end

    # Item +index+ as a cell +width+ wide, a list of segments (see
    # #paint): blank past the last item, a heading in its colour, the lit
    # one as a bar of plain text, the others as a key and a label.
    def cell(index, width)
      item = @items[index]
      return [[' ' * width, :text]] unless item
      return [[label(" #{item.label}", width), :heading]] if item.heading

      prefix = key_width.positive? ? " #{key_text(index)} " : ' '
      return [[fit(prefix + plain(item.label), width), item.color || :bar, true]] if index == @index

      [[prefix, item.color || :key], [label(item.label.to_s, [width - prefix.length, 0].max), :text]]
    end

    # The items on one row as segments, each a key letter and its label,
    # the lit one a bar; the items that do not fit are left off.
    def across_cells
      fitting = fitting_items
      pad = @width - fitting.sum { |item, _| word(item).length + 2 }
      fitting.flat_map { |item, i| across_cell(item, i) } << [' ' * pad, :text]
    end

    private

    # The items, with their indexes, that fit on one row.
    def fitting_items
      used = 0
      @items.each_with_index.take_while { |item, _| (used += word(item).length + 2) <= @width }
    end

    def per_page = @layout.per_page

    def pages = @layout.pages

    def item_rows = @layout.item_rows

    def about? = @items.any?(&:about)

    def status? = @numbers || @hint || pages > 1

    # The rows of the menu: the items', then the about and the status row.
    def rows = item_rows + (about? ? 1 : 0) + (status? ? 1 : 0)

    def fold(key) = key.is_a?(String) ? key.downcase : key

    def read_key = @cursor.key

    # What +key+ takes, as a one-element Array (the value may be +nil+), or
    # +nil+ when it takes nothing.
    def take(key)
      return [@back] if BACK_KEYS.include?(key)
      return [@items[@index].value] if key == :enter
      return [@exits[fold(key)]] if @exits.key?(fold(key))

      item = hotkey(key)
      return unless item

      light(@items.index(item))
      [item.value]
    end

    def hotkey(key)
      return nil unless key.is_a?(String) && key.length == 1
      return nil if @numbers && key.match?(DIGIT)

      @items.find { |i| i.selectable? && i.key && i.key.to_s.downcase == key.downcase }
    end

    def react(key)
      case key
      when *STEP_KEYS.keys then move(STEP_KEYS[key])
      when *SIDE_KEYS.keys then @layout.side(self, SIDE_KEYS[key])
      when *PAGE_KEYS.keys then turn(PAGE_KEYS[key])
      when :home then light(step(-1, 1))
      when :end then light(step(@items.size, -1))
      when :backspace then type(@typed.chop)
      when DIGIT then type(@typed + key) if @numbers
      end
    end

    # The next selectable item from +from+ in direction +dir+, round the end.
    def step(from, dir)
      (1..@items.size).each do |n|
        i = (from + (dir * n)) % @items.size
        return i if @items[i].selectable?
      end
    end

    # The digits typed so far as +digits+: the item of that number lit when
    # there is one; a digit that would make no item's number is dropped.
    def type(digits)
      return if digits.length > MAX_DIGITS
      return if !digits.empty? && !digits.to_i.between?(1, @items.size)

      @typed = digits
      @typed.empty? ? repaint([rows]) : light(@typed.to_i - 1)
    end

    # Lights item +index+, repainting what changed: the rows of the old and
    # the new item, or the whole page when the page turned, then the about
    # and the status row.
    def light(index)
      old    = @index
      turned = @layout.page_of(index) != page
      @index = index
      lines  = turned ? (1..item_rows).to_a : [@layout.line_of(old), @layout.line_of(index)].uniq
      lines << (item_rows + 1) if about?
      lines << rows if status?
      repaint(lines)
    end

    # The segments of menu line +number+ (1-based: the items' rows, then
    # the about row, then the status row).
    def line_segments(number)
      return @layout.segments(number, self) if number <= item_rows
      return about_segments if about? && number == item_rows + 1

      status_segments
    end

    def about_segments = [[fit(" #{plain(@items[@index].about)}", @width), :about]]

    def status_segments
      right = if !@typed.empty? then "##{@typed}"
              elsif pages > 1 then "#{page + 1}/#{pages}"
              else ''
              end
      left = " #{plain(@hint)}"[0, [@width - right.length - 1, 0].max]
      [["#{left}#{' ' * (@width - left.length - right.length)}#{right}", :hint]]
    end

    def word(item) = item.key ? "#{item.key.to_s.upcase} #{plain(item.label)}" : plain(item.label)

    def across_cell(item, index)
      return [[" #{word(item)} ", item.color || :bar, true]] if index == @index
      return [[" #{word(item)} ", :text]] unless item.key

      [[' ', :text], [item.key.to_s.upcase, item.color || :key], [" #{plain(item.label)} ", :text]]
    end

    def key_width
      @key_width ||= @numbers ? @items.size.to_s.length : @items.map { |i| i.key.to_s.length }.max
    end

    def key_text(index)
      key = @numbers ? (index + 1).to_s : @items[index].key.to_s.upcase
      key.rjust(key_width)
    end

    def fit(text, width) = text.length > width ? text[0, width] : text.ljust(width)

    # +text+ without its colours.
    def plain(text) = FrameBuffer.plain(text)

    # A label cut or padded to +width+ columns, its colours kept.
    def label(text, width)
      text = FrameBuffer.clip_ansi(text, width)
      "#{text}#{' ' * (width - FrameBuffer.visible_width(text))}"
    end

    # ── Drawing on an ANSI line ───────────────────────────────────────────

    def draw
      lines = (1..rows).map { |l| paint(line_segments(l)) }
      @session.write(lines.join(Ansi::CRLF))
      @cursor = Cursor.new(@session, row: lines.size, col: @width + 1)
      @session.write(park)
    end

    # +segments+ (<tt>[text, colour, reversed]</tt>, the colour a role of
    # COLORS or an item's own) as ANSI text.
    def paint(segments)
      segments.map do |text, color, reversed|
        sgr = color.is_a?(Symbol) ? @colors[color] : color
        reversed ? "#{sgr}#{Ansi::REVERSE}#{text}#{Ansi::REVERSE_OFF}#{@colors[:text]}" : "#{sgr}#{text}"
      end.join << @colors[:text]
    end

    def repaint(lines)
      out = lines.map { |l| row_at(l, paint(line_segments(l))) }.join
      @session.write(out << park)
    end

    # The cursor to the start of the lit item.
    def park = @cursor.move(@layout.line_of(@index), @layout.column_of(@index, @width))

    # The bytes that write +text+ (exactly #width columns) on row +row+.
    def row_at(row, text)
      out = @cursor.move(row, 1) << text
      @cursor.wrote(@width)
      out
    end

    def finish(result)
      @session.write(@cursor.move(rows, 1) << Ansi::CRLF)
      result
    end
  end
end
require_relative 'selector/layouts'
