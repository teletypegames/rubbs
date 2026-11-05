# frozen_string_literal: true

module Rubbs
  module Modern
    # The modern face of the kit, for an ANSI terminal: the look of a board
    # (Look: its logo, its tabs, its accent colour, the width), the helpers
    # of its screens (Style), a screen of lines (Screen, Lines), the line
    # read at the bottom (Prompt), and the runner of the tabs (Tabs: TAB and
    # the arrows go round them, each keeping its place).
    #
    #   look = Rubbs::Modern::Kit::Look.new(logo: ['MY BOARD'], tabs: { news: 'NEWS', files: 'FILES' })
    #   Rubbs::Modern::Kit::Tabs.new(session, look: look, sides: { news: News.new, files: Files.new }).run
    module Kit
    end
  end
end

require_relative 'kit/style'
require_relative 'kit/screen'
require_relative 'kit/tabs'
