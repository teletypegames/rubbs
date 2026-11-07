# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # A question: solved by typing one of the answers (a String or a list),
      # compared as Hunt.normalize makes them.
      #
      #   answer: ['256 mg', '256 milligrams']
      class Answer < Part
        # The accepted answers, normalized.
        def answers = Array(value).map { |a| Hunt.normalize(a) }.reject(&:empty?)

        # No answer at all.
        def problems(_catalog) = answers.empty? ? ['answer needs at least one answer'] : []

        # Whether +text+ is one of the answers.
        def accept?(text) = answers.include?(Hunt.normalize(text))

        # The caller types.
        def asks? = true
      end
    end
  end
end
