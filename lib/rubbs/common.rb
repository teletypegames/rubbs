# frozen_string_literal: true

module Rubbs
  # What a board needs on either face: the telnet line and the server
  # (Line), the board's declaration (Board), a call's flow and its first and
  # last screens (Call), the screens both faces share (Screens), accounts
  # (Auth), data (Storage), the web (Web), file transfers (Files), text and
  # drawings (Text, Art, Season), the log (Log), the AI (AI, FakeOS).
  module Common
  end
end

require_relative 'common/line'
require_relative 'common/files'
require_relative 'common/board'
require_relative 'common/web'
require_relative 'common/storage'
require_relative 'common/call'
require_relative 'common/screens'
