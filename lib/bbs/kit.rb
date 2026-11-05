# frozen_string_literal: true

module BBS
  # A kit of screens for a board's own menus, on either face, after the look
  # of TTG Gate BBS: on a C64 (Kit::Petscii) a menu bar of tabs over the
  # content, a sub-menu, a hint bar, lists with a lit row and the lit item's
  # details under a rule, CRSR between the tabs, the sub-menu and the
  # content; on a modern terminal (Kit::Modern) a logo over the tabs, lists
  # and menus with a lit row, a top line, a line read at the bottom. Both
  # are pages of a BBS::Pages runner, so only what changed goes out.
  # Everything a board would change (the title, the tabs, the hotkeys, the
  # colours, the logo) is given, not written in.
  module Kit
  end
end

require_relative 'kit/petscii'
require_relative 'kit/modern'
