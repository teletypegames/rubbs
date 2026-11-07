# frozen_string_literal: true

module Rubbs
  module Common
    module Badges
      # The badges of one board (or of the whole network, +board+
      # Rubbs::Common::Badges::NETWORK) and the events it reports, as a
      # board's file declares them with Rubbs.badges:
      #
      #   Rubbs.badges :hackercave do
      #     event :read, kind: String, ref: String
      #
      #     badge :rfc_reader do
      #       title  'RFC Reader'
      #       hint   'Read RFCs in HackerCave BBS.'
      #       emblem '§', :lightgreen
      #       on(:read, kind: 'rfc').distinct(:ref).tiers bronze: 10, silver: 50, gold: 250
      #     end
      #   end
      class Set
        # The board's technical name (a String), its Badge objects in order,
        # and its events by name with the names of their fields.
        attr_reader :board, :badges, :events

        # The set of +board+, declared by the block (evaluated in the set).
        def initialize(board, &block)
          @board  = board.to_s
          @badges = []
          @events = {}
          instance_eval(&block) if block
        end

        # Declares the event +name+ the board reports (Rubbs::Common::Line::Session#achieve)
        # and its +fields+ (name => what it holds, for the reader; only the
        # names are kept).
        def event(name, **fields) = (@events[name.to_s] = fields.keys.map(&:to_s))

        # Declares the badge +key+ (a Badge made by the block); +secret+ and
        # +manual+ as Badge#new says.
        def badge(key, secret: false, manual: false, &)
          @badges << Badge.new(key, board: @board, secret: secret, manual: manual, &)
        end
      end
    end
  end
end
