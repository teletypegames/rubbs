# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # One thing a step asks, the base of the part kinds (Hunt.part): made
      # from its value in the step's YAML, it says what is wrong with that
      # value (#problems), whether a fact solves it (#match?), whether typed
      # words do (#accept?), and whether the caller is to type (#asks?).
      #
      #   class Count < Rubbs::Common::Hunt::Part
      #     def match?(fact) = …
      #   end
      #   Rubbs::Common::Hunt.part :count, Count
      class Part
        # The value of the part in the YAML, as it was read.
        attr_reader :value

        # A part of +value+ (the YAML's value under the part's key).
        def initialize(value)
          @value = value
        end

        # The part's key in the YAML (Hunt.part).
        def key = Hunt.parts.key(self.class).to_s

        # What is wrong with the value, Strings (empty when nothing is), seen
        # against +catalog+ (a Rubbs::Common::Badges::Catalog, for the events
        # and their fields).
        def problems(_catalog) = []

        # Whether +fact+ (a Rubbs::Common::Badges::Fact) solves the part.
        def match?(_fact) = false

        # Whether the typed +text+ solves the part.
        def accept?(_text) = false

        # Whether the caller solves the part by typing (an answer box).
        def asks? = false
      end
    end
  end
end
