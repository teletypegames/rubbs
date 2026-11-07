# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # One step of a Trail: the +clue+, up to two +hints+, the +fragment+ the
      # caller gets when it is solved (or +nil+), and its +parts+ (Part
      # objects, in the order of Hunt.parts), all solved one after the other.
      Step = Data.define(:clue, :hints, :fragment, :parts) do
        # The keys a step may have beside its parts.
        def self.own_keys = %w[clue hints fragment]

        # The step of +hash+ (a step of the YAML) and what is wrong with it:
        # <tt>[step, problems]</tt>, the step +nil+ when it cannot be made.
        def self.read(hash)
          return [nil, ['a step is not a mapping']] unless hash.is_a?(Hash)

          hash = hash.to_h { |k, v| [k.to_s, v] }
          step = build(hash)
          [step, step.shape_problems(hash.keys - own_keys - Hunt.parts.keys)]
        end

        # The step of +hash+ (String keys), its parts in the order of
        # Hunt.parts.
        def self.build(hash)
          new(
            clue:     hash['clue'].to_s.strip,
            hints:    Array(hash['hints']).map(&:to_s),
            fragment: hash['fragment']&.to_s,
            parts:    Hunt.parts.filter_map { |key, klass| klass.new(hash[key]) if hash.key?(key) }
          )
        end

        # The rows +line+ (one line of a clue) takes when it is wrapped at
        # +width+ columns, at least one.
        def self.rows(line, width = C64_CLUE[0])
          rows = line.split.map(&:length).each_with_object([0]) do |len, row|
            row[-1].zero? || row[-1] + 1 + len > width ? row << len : row[-1] += 1 + len
          end
          rows.count(&:positive?).clamp(1, nil)
        end

        # What is wrong with the step itself: no clue, no part, too many
        # hints, a clue too long for a Commodore 64, and the +unknown+ keys.
        def shape_problems(unknown = [])
          [*('no clue' if clue.empty?), *('no part (find, answer, …)' if parts.empty?),
           *('at most two hints' if hints.size > HINT_AFTER.size),
           *("the clue takes more than #{C64_CLUE[1]} lines on a C64" if c64_lines > C64_CLUE[1]),
           *unknown.map { |k| "unknown key #{k}" }]
        end

        # The lines the clue takes on a Commodore 64.
        def c64_lines = clue.split("\n").sum { |line| Step.rows(line) }
      end
    end
  end
end
