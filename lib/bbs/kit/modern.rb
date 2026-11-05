# frozen_string_literal: true

module BBS
  module Kit
    # The modern face of the kit, for an ANSI terminal: the look of a board
    # (Look: its logo, its tabs, its accent colour, the width), the helpers
    # of its screens (Style), a screen of lines (Screen, Lines), the line
    # read at the bottom (Prompt), and the runner of the tabs (Tabs: TAB and
    # the arrows go round them, each keeping its place).
    #
    #   look = BBS::Kit::Modern::Look.new(logo: ['MY BOARD'], tabs: { news: 'NEWS', files: 'FILES' })
    #   BBS::Kit::Modern::Tabs.new(session, look: look, sides: { news: News.new, files: Files.new }).run
    module Modern
    end
  end
end

require_relative 'modern/style'
require_relative 'modern/screen'
require_relative 'modern/tabs'
