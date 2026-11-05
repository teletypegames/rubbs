# frozen_string_literal: true

require_relative 'focus'

module BBS
  module Kit
    module Petscii
      # A C64 board's screens in one runner: the Chrome around a View of the
      # content (the page on top of the stack), the tabs on the bar and a
      # tab's sub-menu under them. CRSR up from the top of a list (or from a
      # page) moves the focus up: to the sub-menu of a tab that has one, and
      # from there (or at once) to the tabs. On the tabs CRSR left and right
      # switch the tabs as the cursor goes (an action place, #action?, waits
      # for RETURN); on the sub-menu they move its bar and RETURN opens. CRSR
      # down goes back to the content. A hotkey of the Chrome opens its place
      # from anywhere (a view's own keys first). ← or RUN/STOP goes back, and
      # from the home section's first screen the runner ends.
      #
      # Each change is drawn on a new Canvas and only the cells that differ
      # from what the C64 shows go out (BBS::Pages).
      #
      # A board says what its places are:
      #
      # [#section_view] the view a key opens (a tab, a sub-menu place)
      # [#action]       what an action place does (a search, a profile)
      # [#action?]      which keys are actions, not sections
      # [#tab_for]      the tab a section belongs to
      # [#top_line]     the line under the bar of a tab without a sub-menu
      class Frame < BBS::Pages
        include Focus

        # The keys the tabs and the sub-menu take while they have the focus.
        FOCUS_KEYS = %i[left right up down enter].freeze
        # The hint bar while the sub-menu has the focus.
        MENU_HINT = [['CRSR', true], [' Move  ', false], ['RETURN', true], [' Open  ', false], ['CRSR down', true],
                     [' List', false]].freeze
        # The hint bar while the tabs have the focus.
        BAR_HINT = [['CRSR', true], [' Tabs  ', false], ['RETURN', true], [' Open  ', false], ['CRSR down', true],
                    [' Back', false]].freeze
        # The hint bar of a page shown over the view (#pop_up).
        PRESS_A_KEY = [['Press a key', false]].freeze

        # [focus] +:main+ (the content), +:menu+ (the sub-menu) or +:bar+
        #         (the tabs)
        # [tab]   the active tab (a Place's key)
        # [chrome] the Chrome
        attr_reader :focus, :tab, :chrome

        # A runner for the C64 caller on +session+ in the frame of +chrome+,
        # starting on the tab +home+ (the first place by default); a line is
        # read on the hint row after +input_label+.
        def initialize(session, chrome:, home: nil, input_label: 'Find:', charset: :lower)
          super(session, face: :petscii, charset: charset)
          @chrome      = chrome
          @home        = home || chrome.places.first&.key
          @input_label = input_label
          @focus       = :main
          @tab         = @home
          @section     = @home
          @menu        = 0
          @bar         = 0
          @status      = nil
        end

        # Runs from +page+ (the home section's view by default) until the
        # caller leaves.
        def run(page = section_view(@home)) = super

        # The first screen: the home section's.
        def start(page = section_view(@home))
          @section = @home
          @tab = @home
          super
        end

        # The view on top.
        def view = page

        # Answers one key: the tabs or the sub-menu while they have the
        # focus, CRSR up to them, RUN/STOP back, then the view's own keys,
        # then the hotkeys.
        def handle(key) = frame_key(key) || view.handle(key) || hotkey(key)

        # The screen as it is now: the frame around the view, the line being
        # read or the hint bar, the cursor resting at the end of the hint
        # row.
        def draw(canvas)
          @chrome.bar(canvas, active: @tab, cursor: (bar_place.key if @focus == :bar))
          menu? ? @chrome.menu_bar(canvas, lit: lit, focused: @focus == :menu) : top_line(canvas)
          view.draw(canvas)
          line ? input_line(canvas) : @chrome.hint(canvas, hint)
          cursor(Layout::HINT_ROW, Layout::HINT_WIDTH)
        end

        # Over another view: the focus back on the content.
        def push(target)
          @focus = :main
          super
        end

        # Back a screen; from a section's first one to the home section, and
        # from there the runner ends.
        def back
          @focus = :main
          return super if stack.size > 1
          return quit if @section == @home

          go(@home)
        end

        # Shows +target+ (a TextView) over the view until a key (or until
        # the block answers one, see BBS::Pages#show), with +hint+ on the
        # hint bar; the answer.
        def pop_up(target, hint: PRESS_A_KEY, &)
          target.hint = hint
          show(target, &)
        end

        # Opens the place +key+: +:quit+ ends, an action (#action?) runs, a
        # section's view (#section_view) takes the stack, its tab
        # (#tab_for) lit.
        def go(key)
          return quit if key == :quit

          @focus = :main
          return action(key) if action?(key)

          target = section_view(key)
          return unless target

          @section = key
          tab = tab_for(key)
          @tab = tab if tab
          reset(target)
        end

        # The view the place +key+ opens, or +nil+. A board defines it.
        def section_view(_key) = nil

        # Whether the place +key+ is an action (#action) rather than a
        # section; none by default.
        def action?(_key) = false

        # Runs the action place +key+; nothing by default.
        def action(_key) = nil

        # The tab the section +key+ belongs to: the place of that key, the
        # sub-menu's tab for a place of the sub-menu, else +nil+ (the tab
        # stays).
        def tab_for(key)
          return key if @chrome.place(key)
          return @chrome.menu_tab if @chrome.menu.any? { |i| i.key == key } || @chrome.under.key?(key)

          nil
        end

        # Draws the line under the bar of a tab without a sub-menu; nothing
        # by default.
        def top_line(_canvas) = nil

        private

        # The keys the frame takes before the view: the tabs' or the
        # sub-menu's while they have the focus, CRSR up to them, RUN/STOP.
        def frame_key(key)
          return focus_key(key) if focused?(key)
          return climb if key == :up && climb?

          back if key == :escape
        end

        def focused?(key) = @focus != :main && FOCUS_KEYS.include?(key)

        def hint = @status || { menu: MENU_HINT, bar: BAR_HINT }.fetch(@focus) { view.hint }

        # A hotkey opens its place from anywhere.
        def hotkey(key)
          return unless key.is_a?(String) && @chrome.hotkeys.key?(key.downcase)

          go(@chrome.hotkeys[key.downcase]) || true
        end

        # The line being read, on the hint row: its label (the frame's
        # +input_label+ when it has none), the words, a reversed cell for the
        # cursor.
        def input_line(canvas)
          label = line.label.to_s.empty? ? @input_label : line.label.to_s
          text  = line.text
          canvas.text(Layout::HINT_ROW, 0, label, Canvas::LIGHT_GREEN)
          canvas.text(Layout::HINT_ROW, label.length + 1, text, Canvas::WHITE)
          canvas.text(Layout::HINT_ROW, label.length + 1 + text.length, ' ', Canvas::WHITE, rvs: true)
        end
      end
    end
  end
end
