# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      # The place a forwarded call asks the board to open (+BBS_GOTO+, sent by
      # Rubbs::Common::Line::Gateway#to): a line that answers +forwarded+ (the
      # forwarded variables, a Hash) includes it.
      #
      #   place = session.take_goto   # => "machine:Q99775", once
      module Goto
        # The place asked for, the first time it is asked; +nil+ after that,
        # or when none was asked. A board opens it instead of its first
        # screen, and falls back to that screen when it has no such place.
        def take_goto
          return nil if @goto_taken

          @goto_taken = true
          place = forwarded['BBS_GOTO'].to_s.strip
          place.empty? ? nil : place
        end
      end
    end
  end
end
