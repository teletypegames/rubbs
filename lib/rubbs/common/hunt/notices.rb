# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # What the caller is told when a step is solved and when a hunt is
      # over, and the fact a finish is for the badges.
      module Notices
        module_function

        # The notice of step +step+ (0-based) of +trail+ solved, with its
        # fragment.
        def found(trail, step)
          fragment = trail.steps[step].fragment
          words = "The Hunt, #{trail.title}: step #{step + 1} solved."
          words += " Your fragment: #{fragment}." if fragment
          "#{words} The next clue waits on your Hunt page."
        end

        # The notice of +trail+ finished (+finish+ as
        # Engine#finish_of answers it), with the place on the list.
        def home(trail, finish)
          place = finish['rank'] ? " You are number #{finish['rank']} on the list." : ''
          "The Hunt, #{trail.title}: you made it home!#{place}"
        end

        # The +hunt_finished+ Rubbs::Common::Badges::Fact of +finish+ in
        # +trail+: +ref+ the slug, +in_season+ yes or no, +hints+, +rank+.
        def fact(trail, finish)
          fields = { ref: trail.slug, in_season: finish['season'] ? 'yes' : 'no', hints: finish['hints'], rank: finish['rank'] }
          Badges::Fact.make(name: 'hunt_finished', board: Badges::NETWORK, fields: fields)
        end
      end
    end
  end
end
