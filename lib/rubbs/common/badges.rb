# frozen_string_literal: true

require_relative 'badges/rule'
require_relative 'badges/fact'
require_relative 'badges/badge'
require_relative 'badges/set'
require_relative 'badges/catalog'
require_relative 'badges/engine'
require_relative 'badges/service'
require_relative 'badges/reporter'

module Rubbs
  module Common
    # Badges for the accounts of a network, earned on any board and kept on
    # the Central. A board declares its badges in a file of its own with
    # Rubbs.badges (a Set: the events it reports and the badges, each a
    # Badge with a Rule); the Central loads every board's and counts the
    # events (Service, Engine); a board loads its own and sends the events
    # of its signed-in callers (Reporter), the +call+, +use+ and +hangup+
    # ones by itself and its own with Rubbs::Common::Line::Session#achieve.
    #
    #   Rubbs.badges :network do
    #     badge :tourist do
    #       title  'Tourist'
    #       hint   'Call five different boards.'
    #       emblem '♦', :cyan
    #       on(:call).distinct(:board).reaches 5
    #     end
    #   end
    #
    #   Rubbs.board 'HackerCave BBS', HackerCaveBBS do
    #     central TTG::CENTRAL
    #     badges  :hackercave                   # sends this board's events
    #   end
    #
    #   session.achieve :read, kind: 'rfc', ref: '1149'
    module Badges
      # The board of the badges that belong to the whole network.
      NETWORK = 'network'

      class << self
        # The Catalog of this process.
        def catalog = @catalog ||= Catalog.new

        # Forgets every badge (for a test).
        def reset = @catalog = Catalog.new

        # Runs the block with an empty catalog of its own and gives that
        # catalog back; the process's stays as it was (for a check that
        # loads one board's file).
        def isolated
          outer = catalog
          @catalog = Catalog.new
          yield
          @catalog
        ensure
          @catalog = outer
        end

        # The time zone of the derived fields (Fact.make); default
        # <tt>Europe/Budapest</tt>.
        def time_zone = @time_zone || 'Europe/Budapest'

        # Sets the time zone of the derived fields (see #time_zone).
        attr_writer :time_zone

        # Declares the badges of +board+ (a Set made by the block) into the
        # catalog. Returns the Set.
        def define(board, &)
          set = Set.new(board, &)
          catalog.add(set)
          set
        end

        # The words a caller is told for an earned +badge+ (an answer of
        # Service#record): the emblem, the title, the tier, the hint.
        def announcement(badge)
          tier = badge['tier'].to_s.empty? ? '' : " (#{badge['tier']})"
          "Badge earned: #{badge['emblem']} #{badge['title']}#{tier}. #{badge['hint']}".strip
        end

        # The event +name+ with +fields+ of the caller on +session+, through
        # the board's Reporter (Rubbs.config.badges): the queued entry, +nil+
        # when nothing went or there is no Reporter.
        def report(session, name, fields = {}) = Rubbs.config.badges&.report(session, name, fields)

        # The +call+ event of +session+ (Reporter#called); nothing without a
        # Reporter.
        def called(session) = Rubbs.config.badges&.called(session)

        # The +hangup+ event of +session+ (Reporter#hung_up); nothing without
        # a Reporter.
        def hung_up(session) = Rubbs.config.badges&.hung_up(session)
      end
    end
  end
end
