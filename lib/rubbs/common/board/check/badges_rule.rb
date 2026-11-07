# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      # The rule of a board's file of badges (Rubbs.badges), beside the
      # rules of the shape every board has.
      module Check
        rule(:badges, 'the badges of badges.rb are whole (Rubbs::Common::Badges::Catalog#problems)') do |board|
          next unless board.file?('badges.rb')

          catalog = Badges.isolated { load board.full_path('badges.rb') }
          catalog.problems.each { |problem| board.fail('badges.rb', problem) }
        rescue StandardError, ScriptError => e
          board.fail('badges.rb', "does not load: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
