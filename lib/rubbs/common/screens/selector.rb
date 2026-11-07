# frozen_string_literal: true

require_relative '../../petscii'
require_relative '../../petscii/colors'

module Rubbs
  module Common
    module Screens
      # A menu at the cursor for a line-by-line board, on a Commodore 64 and a
      # modern terminal alike: the items one under the other (in one column or
      # several, or side by side on one row), the chosen one lit as a reversed
      # bar that the cursor keys move. RETURN takes the lit item; an item's own
      # key (a letter or a digit) takes it at once, so a caller who knows the
      # menu types as before. With +numbers+ the items are numbered instead, and
      # the digits typed light the item of that number. More items than a page
      # holds turn into pages.
      #
      # Like Rubbs::Common::Screens::Field it draws from where the cursor is (at the start of a
      # line) downwards and moves with a Rubbs::Common::Screens::Cursor, so a C64 never gets HOME;
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
      #   items = [Rubbs::Common::Screens::Selector.item('latest posts', key: 'l', value: :latest),
      #            Rubbs::Common::Screens::Selector.item('log off', key: 'q', value: :quit)]
      #   case Rubbs::Common::Screens::Selector.new(session, items, width: 38).run
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

        # The colours of the roles, from the C64 palette (Rubbs::Petscii::Colors):
        # +text+ the labels, +key+ the keys and numbers, +bar+ the lit cell
        # (reversed), +heading+ the headings, +about+ the about row, +hint+ the
        # status row.
        COLORS = {
          text:    Petscii::Colors::LG,
          key:     Petscii::Colors::YE,
          bar:     Petscii::Colors::CY,
          heading: Petscii::Colors::DG,
          about:   Petscii::Colors::GR,
          hint:    Petscii::Colors::DG
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

        # +items+ with every key used once: an item whose key +taken+ (keys
        # kept for others) or an item before it has keeps no key; with +log+
        # (a log tag) each such clash is a warning. Returns the items (the
        # same objects).
        def self.distinct(items, taken: [], log: nil)
          taken = taken.dup
          items.each do |item|
            next unless item.key

            if taken.include?(item.key)
              Rubbs.log(log, "the key #{item.key} of #{item.value} is taken", level: :warn) if log
              item.key = nil
            end
            taken << item.key
          end
        end

        # A heading Item: +label+ (ANSI colours allowed) shown in the heading
        # colour, never lit. An empty label keeps a place empty.
        def self.heading(label = '') = Item.new(label: label, heading: true)

        # A numbered menu of +objects+, each labelled by the block; the object
        # taken, or +back+. The other options are those of ::new.
        #
        #   post = Rubbs::Common::Screens::Selector.list(session, posts, width: 38, height: 18, &:title)
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
        # [item_exits] keys that act on the lit item: #run returns
        #           <tt>[value, item value]</tt> for them, e.g.
        #           <tt>{ 'd' => :delete }</tt> gives <tt>[:delete, post]</tt>
        # [back]    what #run returns for RUN/STOP, ← or Esc
        # [colors]  colours of the roles over COLORS
        # [indent]  columns of air left of the menu (to centre it)
        #
        # Raises ArgumentError when no item can be selected.
        def initialize(
          session,
          items,
          width:,
          height: nil,
          columns: 1,
          index: nil,
          numbers: false,
          across: false,
          hint: nil,
          exits: {},
          item_exits: {},
          back: nil,
          colors: {},
          fill: false,
          indent: 0
        )
          raise ArgumentError, 'a selector needs an item to select' unless items.any?(&:selectable?)

          @session = session
          @items   = items
          @width   = [width, 4].max
          @layout  = across ? Row.new(items.size) : Columns.new(items.size, height: height, columns: columns, fill: fill)
          @index   = first_index(index)
          @numbers = numbers
          @hint    = hint
          @exits   = fold_keys(exits)
          @item_exits = fold_keys(item_exits)
          @back    = back
          @colors  = self.class::COLORS.merge(colors)
          @typed   = +''
          @indent  = indent
        end

        # Draws the menu, then reads keys until an item is taken or the caller
        # goes back; the cursor ends on the line under the menu.
        #
        # Returns the taken item's +value+, an +exits+ value, an
        # <tt>[item_exits value, lit item's value]</tt> pair, or +back+. Raises
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

        private

        def per_page = @layout.per_page

        def pages = @layout.pages

        def item_rows = @layout.item_rows

        def about? = @items.any?(&:about)

        def status? = @numbers || @hint || pages > 1

        # The rows of the menu: the items', then the about and the status row.
        def rows = item_rows + (about? ? 1 : 0) + (status? ? 1 : 0)

        def fold(key) = key.is_a?(String) ? key.downcase : key

        def fold_keys(keys) = keys.transform_keys { |k| fold(k) }

        def read_key = @cursor.key

        # Item +index+ when it can be lit, else the first that can.
        def first_index(index) = index && @items[index]&.selectable? ? index : step(-1, 1)

        # The next selectable item from +from+ in direction +dir+, round the end.
        def step(from, dir)
          (1..@items.size).each do |n|
            i = (from + (dir * n)) % @items.size
            return i if @items[i].selectable?
          end
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
      end
    end
  end
end
require_relative 'selector/layouts'
require_relative 'selector/cells'
require_relative 'selector/keys'
