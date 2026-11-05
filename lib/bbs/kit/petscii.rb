# frozen_string_literal: true

module BBS
  module Kit
    # The C64 face of the kit, 40×25 in the lower/upper character set: the
    # grid and its drawing helpers (Layout), the frame of every screen
    # (Chrome: the menu bar with the tabs, a sub-menu under it, the hint
    # bar), the views of the content (View, Picker, MenuView, TextView) and
    # the runner that holds them together (Frame: the focus on the content,
    # the sub-menu or the tabs, CRSR between them, hotkeys, the line read on
    # the hint row).
    #
    #   chrome = BBS::Kit::Petscii::Chrome.new(title: 'MY BOARD', places: [[:news, 'NEWS'], [:files, 'FILES']])
    #   class Board < BBS::Kit::Petscii::Frame
    #     def section_view(key) = key == :news ? news_view : files_view
    #   end
    #   Board.new(session, chrome: chrome).run(news_view)
    module Petscii
      # The C64 screen the kit draws on (BBS::Petscii::Canvas).
      Canvas = BBS::Petscii::Canvas
    end
  end
end

require_relative 'petscii/layout'
require_relative 'petscii/chrome'
require_relative 'petscii/views'
require_relative 'petscii/frame'
