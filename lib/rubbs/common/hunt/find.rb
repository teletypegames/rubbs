# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # A place to go: solved by an event of the caller on a board, the same
      # the boards send for the badges. Its value names the +board+, the
      # +event+ and any of the event's fields, each a value or a list of
      # values (any of them), compared without regard to case:
      #
      #   find: { board: hackercave, event: read, kind: rfc, ref: '1149' }
      #   find: { board: pixelia, event: paint }
      class Find < Part
        # The board, the event and the filter on the event's fields (String
        # keys).
        attr_reader :board, :event, :filter

        # A place of +value+ (a Hash).
        def initialize(value)
          super
          hash    = value.is_a?(Hash) ? value.to_h { |k, v| [k.to_s, v] } : {}
          @board  = hash.delete('board').to_s
          @event  = hash.delete('event').to_s
          @filter = hash
        end

        # A missing board or event, an event no board declares, a field the
        # event does not have.
        def problems(catalog)
          return ['find needs a board and an event'] if board.empty? || event.empty?

          fields = catalog.events[event] or return ["no board reports the event #{event}"]
          filter.keys.reject { |f| fields.include?(f) }.map { |f| "the event #{event} has no field #{f}" }
        end

        # Whether +fact+ is the event on the board with every field of the
        # filter.
        def match?(fact)
          fact.name == event && fact.board == board && filter.all? { |key, wanted| same?(wanted, fact.field(key)) }
        end

        private

        def same?(wanted, actual)
          return Array(wanted).any? { |w| same?(w, actual) } if wanted.is_a?(Array)
          return Array(actual).any? { |a| same?(wanted, a) } if actual.is_a?(Array)

          wanted.to_s.casecmp?(actual.to_s)
        end
      end
    end
  end
end
