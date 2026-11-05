# frozen_string_literal: true

module Rubbs
  module Petscii
    module Kit
      class Frame < Common::Screens::Pages
        # Where the focus of a Frame goes: from the content up to the
        # sub-menu (on its tab) and to the tabs, along them with CRSR left and
        # right, and down again.
        module Focus
          private

          def menu? = @chrome.menu_tab && @tab == @chrome.menu_tab && @chrome.menu.any?

          def bar_place = @chrome.places[@bar]

          # Answers +key+ on the tabs or the sub-menu; the focus after it
          # (the key is always taken).
          def focus_key(key)
            @focus == :bar ? bar_key(key) : menu_key(key)
            @focus
          end

          def climb? = to_menu? || to_bar?

          # CRSR up from the content: the sub-menu, or the tabs.
          def climb = to_menu? ? to_menu : to_bar

          # The place of the sub-menu lit: the cursor's while the menu has the
          # focus, else the section's (or the one it is under).
          def lit
            return @chrome.menu[@menu].key if @focus == :menu

            section = view.section || @section
            @chrome.under.fetch(section, section)
          end

          # CRSR up from the top of a list, or from a screen without one.
          def at_top? = !view.is_a?(Picker) || view.at_top?

          def to_menu? = @focus == :main && menu? && at_top?

          def to_menu
            @menu = @chrome.menu.index { |i| i.key == lit } || 0
            @focus = :menu
          end

          def to_bar? = @focus == :main && !menu? && at_top? && @chrome.places.any?

          def to_bar
            @bar = @chrome.places.index { |p| p.key == @tab } || 0
            @focus = :bar
          end

          def menu_key(key)
            case key
            when :left, :right then @menu = (@menu + (key == :left ? -1 : 1)) % @chrome.menu.size
            when :down then @focus = :main
            when :up then to_bar
            when :enter then go(@chrome.menu[@menu].key)
            end
          end

          # The tabs: left and right switch the tabs as the cursor goes (an
          # action waits for RETURN), RETURN opens, down goes back.
          def bar_key(key)
            case key
            when :left, :right
              @bar = (@bar + (key == :left ? -1 : 1)) % @chrome.places.size
              follow_bar
            when :down then @focus = :main
            when :enter then go(bar_place.key)
            end
          end

          def follow_bar
            place = bar_place.key
            return if action?(place) || place == @tab

            go(place)
            @focus = :bar
          end
        end
      end
    end
  end
end
