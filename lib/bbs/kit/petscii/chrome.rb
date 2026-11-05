# frozen_string_literal: true

module BBS
  module Kit
    module Petscii
      # The frame around every screen of a Frame: the menu bar on row 0 (the
      # title, then the places, the active one lit and the one under the
      # cursor white while the tabs have the focus), a tab's sub-menu or line
      # on row 1, and the hint bar on row 24. What it shows and in which
      # colours is given when it is made:
      #
      #   BBS::Kit::Petscii::Chrome.new(
      #     title:    'TTG GATE',
      #     places:   [[:own, 'OWN'], [:discover, 'GLOBAL'], [:account, 'PROFILE']],
      #     menu:     [[:search, '/Find', 0], [:browse, 'Browse', 0]],
      #     menu_tab: :discover,
      #     hotkeys:  { 'o' => :own, 'q' => :quit }
      #   )
      class Chrome
        # A place of the menu bar: its +key+, +label+, the index of the letter
        # that opens it, and the column it starts at.
        Place = Data.define(:key, :label, :hotkey, :col) do
          # The letter that opens it, lower case.
          def letter = label[hotkey].downcase
        end

        # A place of the sub-menu: +key+ the section it opens, +label+, the
        # index of its +hotkey+ sign in the label, and the column it starts
        # at.
        Item = Data.define(:key, :label, :hotkey, :col) do
          # The sign that opens it, lower case.
          def letter = label[hotkey].downcase
        end

        # The colours by default:
        #
        # [bar]        the menu bar (reversed cells)
        # [lit]        the active place on the bar
        # [key]        the cell of a place's key on the bar
        # [cursor]     the place under the cursor while the tabs have the focus
        # [menu]       a place of the sub-menu
        # [menu_key]   its sign
        # [menu_lit]   the lit place of the sub-menu
        # [menu_focus] the lit place while the sub-menu has the focus
        # [hint]       the words of the hint bar
        # [hint_key]   its keys
        COLORS = {
          bar:        Canvas::CYAN,
          lit:        Canvas::PURPLE,
          key:        Canvas::YELLOW,
          cursor:     Canvas::WHITE,
          menu:       Canvas::LIGHT_GREY,
          menu_key:   Canvas::YELLOW,
          menu_lit:   Canvas::LIGHT_GREEN,
          menu_focus: Canvas::CYAN,
          hint:       Canvas::WHITE,
          hint_key:   Canvas::YELLOW
        }.freeze

        # [title]    the board's name at the left of the bar
        # [places]   the places of the bar (Place)
        # [menu]     the places of the sub-menu (Item)
        # [menu_tab] the tab (a Place's key) the sub-menu belongs to, or +nil+
        # [under]    the sections that light a place of the sub-menu other
        #            than their own (section => the place's key)
        # [hotkeys]  the letters that open a place from anywhere (a letter =>
        #            a key), the sub-menu's signs among them
        # [colors]   COLORS with the board's own
        attr_reader :title, :places, :menu, :menu_tab, :under, :hotkeys, :colors

        # A frame of +title+ and +places+ ([key, label] each, the first letter
        # the key's), the sub-menu +menu+ of the tab +menu_tab+ ([key, label,
        # index of the sign] each), +under+, +hotkeys+ (the sub-menu's signs
        # are added) and +colors+ over COLORS.
        def initialize(title:, places:, menu: [], menu_tab: nil, under: {}, hotkeys: {}, colors: {})
          @title    = title.to_s
          @places   = lay_out_places(places).freeze
          @menu     = lay_out_menu(menu).freeze
          @menu_tab = menu_tab
          @under    = under.freeze
          @hotkeys  = hotkeys.merge(@menu.to_h { |i| [i.letter, i.key] }).freeze
          @colors   = COLORS.merge(colors).freeze
        end

        # Draws the menu bar: the title, each place with the cell of its key
        # in the key colour, +active+ (a Place's key) lit and +cursor+ (a
        # Place's key, while the tabs have the focus) in the cursor colour.
        def bar(canvas, active:, cursor: nil)
          canvas.text(Layout::BAR_ROW, 0, ' ' * Layout::WIDTH, @colors[:bar], rvs: true)
          canvas.text(Layout::BAR_ROW, 1, @title, @colors[:bar], rvs: true)
          @places.each { |place| draw_place(canvas, place, place_color(place.key, active, cursor)) }
        end

        # Draws the sub-menu: +lit+ (an Item's key) a reversed bar, in the
        # focus colour while the menu has the focus (+focused+).
        def menu_bar(canvas, lit:, focused:)
          @menu.each do |item|
            if item.key == lit
              canvas.text(Layout::MENU_ROW, item.col, item.label, @colors[focused ? :menu_focus : :menu_lit], rvs: true)
            else
              canvas.text(Layout::MENU_ROW, item.col, item.label, @colors[:menu])
              canvas.text(Layout::MENU_ROW, item.col + item.hotkey, item.label[item.hotkey], @colors[:menu_key])
            end
          end
        end

        # Draws +parts+ ([text, colour] each) on the row under the bar: the
        # line of a tab without a sub-menu.
        def line(canvas, parts) = Layout.runs(canvas, Layout::MENU_ROW, 1, parts)

        # Draws the hint bar: +parts+ of [text, key?], the keys and the words
        # in their colours.
        def hint(canvas, parts)
          Layout.runs(
            canvas,
            Layout::HINT_ROW,
            1,
            parts.map { |t, k| [t, k ? @colors[:hint_key] : @colors[:hint]] },
            limit: Layout::HINT_WIDTH
          )
        end

        # The Place of +key+, or +nil+.
        def place(key) = @places.find { |p| p.key == key }

        private

        def draw_place(canvas, place, color)
          canvas.text(Layout::BAR_ROW, place.col - 1, " #{place.label} ", color, rvs: true)
          canvas.text(Layout::BAR_ROW, place.col + place.hotkey, place.label[place.hotkey], @colors[:key], rvs: true)
        end

        def place_color(key, active, cursor)
          return @colors[:cursor] if key == cursor
          return @colors[:lit] if key == active

          @colors[:bar]
        end

        def lay_out_places(places)
          places.each_with_object([]) do |(key, label), laid|
            col = laid.empty? ? @title.length + 4 : laid.last.col + laid.last.label.length + 3
            laid << Place.new(key, label, 0, col)
          end
        end

        def lay_out_menu(menu)
          menu.each_with_object([]) do |(key, label, hotkey), laid|
            col = laid.empty? ? 0 : laid.last.col + laid.last.label.length + 1
            laid << Item.new(key, label, hotkey || 0, col)
          end
        end
      end
    end
  end
end
