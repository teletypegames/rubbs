# frozen_string_literal: true

require 'bbs'
require_relative 'lib/domain'
require_relative 'lib/ui/modern'
require_relative 'lib/ui/petscii'

# A guestbook on a telnet line, on a modern terminal and on a Commodore 64.
BBS.board 'Sample BBS', SampleBBS do
  modern  UI::Modern::APP
  petscii UI::Petscii
  goodbye 'This is the sample board of rubbs.'
end
