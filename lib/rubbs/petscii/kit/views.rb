# frozen_string_literal: true

module Rubbs
  module Petscii
    module Kit
      # A view in the content area of a Frame: a page that draws itself on a
      # Canvas, tells the hint bar its keys, and answers the keys that are
      # its own (the others go to the Frame's hotkeys).
      class View < Common::Screens::Page
        # The keys on the hint bar: [text, key?] each.
        def hint = []

        # The section this view belongs to (the place of the sub-menu it
        # lights), +nil+ for the one it was opened in.
        def section = nil
      end

      # A view with a list of items and a lit one, +per_page+ a page: CRSR
      # up and down move (past the edge of a page to the next one), + and -
      # turn the pages, a digit takes that place of the page (0 the tenth),
      # RETURN takes the lit one (#take).
      class Picker < View
        key(:up) { move(-1) }
        key(:down) { move(1) }
        key('+') { turn(1) }
        key('-') { turn(-1) }
        key(:enter) { selected ? take(selected) : pass }
        key(/\A\d\z/) do |digit|
          slot = (digit.to_i - 1) % 10
          pass unless slot < @per_page
          next unless on_page[slot]

          @index = slot
          take(selected)
        end

        # [items] the list
        # [index] the lit item's place on its page
        # [page]  the page shown, from 0
        attr_reader :items, :index, :page

        # A picker of +items+, +per_page+ a page.
        def initialize(items, per_page:)
          super()
          @items    = items
          @per_page = per_page
          @page     = 0
          @index    = 0
        end

        # The pages the items take (at least one).
        def pages_count = [(@items.size + @per_page - 1) / @per_page, 1].max

        # The items of the page shown.
        def on_page = @items[@page * @per_page, @per_page] || []

        # The lit item, or +nil+.
        def selected = on_page[@index]

        # Whether the first item of the first page is lit.
        def at_top? = @page.zero? && @index.zero?

        # Moves the lit item +delta+ places, over the edge of the page.
        def move(delta)
          slot = @index + delta
          if slot.negative? && @page.positive?
            @page -= 1
            @index = on_page.size - 1
          elsif slot >= on_page.size && @page < pages_count - 1
            @page += 1
            @index = 0
          else
            @index = slot.clamp(0, [on_page.size - 1, 0].max)
          end
        end

        # Turns +delta+ pages, the first item of a new page lit.
        def turn(delta)
          target = (@page + delta).clamp(0, pages_count - 1)
          @index = 0 unless target == @page
          @page = target
        end

        # Keeps the place of the list when its items change: the same page
        # and place where they still exist.
        def reload_items(items)
          @items = items
          @page  = @page.clamp(0, pages_count - 1)
          @index = @index.clamp(0, [on_page.size - 1, 0].max)
        end

        # What RETURN does with the lit +item+; nothing by default.
        def take(_item) = nil

        # "1/5" when there is more than one page.
        def page_mark = pages_count > 1 ? "#{@page + 1}/#{pages_count}" : ''
      end

      # A menu in the content area: an entry a row (its number, its name, a
      # dotted leader, its count), the lit one a cyan bar, and under a rule
      # what the lit entry is about. RETURN or its digit takes it (the
      # entry's action).
      class MenuView < Picker
        # Entries a page by default.
        PER_PAGE = 12
        # The keys on the hint bar.
        HINT = [['CRSR', true], [' Move  ', false], ['RETURN', true], [' Open  ', false]].freeze

        # An entry: its +name+, the +count+ at the edge, the lines it is
        # +about+, and its +action+ (a callable).
        Entry = Data.define(:name, :count, :about, :action)

        # [section] the section the menu lights
        # [title]   its title row
        attr_reader :section, :title

        # A menu of +entries+ under +title+ in +color+, lighting +section+;
        # +empty+ is what it says without one.
        def initialize(entries, title:, color:, section:, empty: 'Nothing here yet.', per_page: PER_PAGE)
          super(entries, per_page: per_page)
          @title   = title
          @color   = color
          @section = section
          @empty   = empty
        end

        # Runs the +entry+'s action.
        def take(entry) = entry.action.call

        # The keys: with more than one page +/- too, else ← back.
        def hint = pages_count > 1 ? HINT + [['+/-', true], [' Page', false]] : HINT + [['←', true], [' Back', false]]

        # Draws the title row, the entries of the page and the lit one's
        # about lines under a rule.
        def draw(canvas)
          Layout.band(canvas, @title, [@items.size, page_mark].reject { |s| s.to_s.empty? }.join('  '), @color)
          return canvas.text(Layout.row(2), 1, @empty, Canvas::YELLOW) if @items.empty?

          on_page.each_with_index { |entry, slot| row(canvas, Layout.row(2 + slot), entry, slot) }
          about(canvas, Layout.row(3 + @per_page))
        end

        private

        # The chosen entry's about lines under a rule at +top+.
        def about(canvas, top)
          Layout.rule(canvas, top)
          Array(selected&.about).first(4).each_with_index do |line, i|
            canvas.text(top + 1 + i, 1, Layout.plain(line)[0, Layout::EDGE - 1], i.zero? ? Canvas::WHITE : Canvas::LIGHT_GREY)
          end
        end

        def row(canvas, row, entry, slot)
          number = format('%02d', ((@page * @per_page) + slot + 1) % 100)
          count  = entry.count.to_s
          name, leader = name_and_leader(entry, count)
          if slot == @index
            canvas.text(row, 0, "#{number} #{name}#{leader}#{count}".ljust(Layout::WIDTH), Canvas::CYAN, rvs: true)
          else
            Layout.runs(canvas, row, 0, [[number, Canvas::YELLOW], [' ', nil], [name, Canvas::WHITE],
                                         [leader, Canvas::DARK_GREY], [count, Canvas::CYAN]])
          end
        end

        # The entry's name cut to fit beside +count+, and the dots between.
        def name_and_leader(entry, count)
          name = Layout.plain(entry.name)[0, Layout::WIDTH - 6 - count.length - 2]
          [name, " #{'.' * [Layout::WIDTH - 4 - name.length - count.length - 2, 0].max} "]
        end
      end

      # A page of text in the content area: a help, a message, or a question.
      # +lines+ are [text, colour] each (a String is light grey); +keys+ the
      # chips under them, [key, word] each.
      class TextView < View
        # The keys on the hint bar by default.
        HINT = [['←', true], [' Back', false]].freeze

        # A page titled +title+ in +color+ of +lines+, lighting +section+,
        # with the chips +keys+ and the hint bar +hint+ (HINT by default).
        def initialize(title, lines, color:, section: nil, keys: [], hint: nil)
          super()
          @title   = title
          @lines   = lines
          @color   = color
          @section = section
          @keys    = keys
          @hint    = hint
        end

        # The section the page lights.
        attr_reader :section
        # The keys on the hint bar; Frame#pop_up sets "Press a key" for a
        # page shown over the current one.
        attr_writer :hint

        # The keys on the hint bar.
        def hint = @hint || self.class::HINT

        # Draws the title row, the lines and the chips.
        def draw(canvas)
          Layout.band(canvas, @title, '', @color)
          @lines.first(Layout::ROWS - 3).each_with_index do |line, i|
            text, color = line.is_a?(String) ? [line, Canvas::LIGHT_GREY] : line
            canvas.text(Layout.row(2 + i), 1, Layout.plain(text)[0, Layout::EDGE - 1], color)
          end
          chips(canvas, Layout.row(3 + @lines.size))
        end

        private

        def chips(canvas, row)
          col = 1
          @keys.each do |key, word|
            col = Layout.chip(canvas, row, col, key, Canvas::YELLOW)
            col = Layout.chip(canvas, row, col, word, Canvas::ORANGE) + 2
          end
        end
      end
    end
  end
end
