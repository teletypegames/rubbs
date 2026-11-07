# frozen_string_literal: true

require_relative 'hunt/part'
require_relative 'hunt/find'
require_relative 'hunt/answer'
require_relative 'hunt/step'
require_relative 'hunt/trail'
require_relative 'hunt/book'
require_relative 'hunt/engine'
require_relative 'hunt/notices'
require_relative 'hunt/service'

module Rubbs
  module Common
    # A treasure hunt across the boards of a network, kept on the Central: a
    # chain of steps, each a clue and what solves it, written as YAML files
    # (Trail, Book). A step's parts are of the kinds registered here (#part):
    # Find is solved by an event the boards already send for the badges (a
    # Rubbs::Common::Badges::Fact, watched through Badges.observers), Answer
    # by words the caller types. The Service keeps who is where (Engine) and
    # tells the caller, on any board, what they found.
    #
    #   # content/hunts/2026/w46-avian-route.yml
    #   title: The Avian Route
    #   steps:
    #     - clue: Find the April document that flies datagrams on wings.
    #       find: { board: hackercave, event: read, kind: rfc, ref: '1149' }
    #       fragment: PIGEON
    #     - clue: How heavy is a typical MTU, by that standard?
    #       answer: ['256 mg', '256 milligrams']
    #
    #   Rubbs::Common::Hunt.directory = File.join(__dir__, 'content', 'hunts')
    #   central serve: …, services: [Rubbs::Common::Badges::Service, Rubbs::Common::Hunt::Service]
    module Hunt
      # How long after a step opened each of its hints can be seen, seconds.
      HINT_AFTER = [12 * 3600, 36 * 3600].freeze
      # Seconds a caller waits after a wrong answer.
      WRONG_WAIT = 30
      # Answers a caller may give in an hour.
      ANSWERS_AN_HOUR = 20
      # The widest line of a clue on a Commodore 64, and how many lines it may
      # take there.
      C64_CLUE = [38, 8].freeze

      class << self
        # The kinds of a step's parts, key (a String) => a Part subclass, in
        # the order the parts of one step are solved.
        def parts = @parts ||= {}

        # Registers +klass+ (a Part subclass) as the part kind +key+: a step
        # with that key in its YAML gets one. Returns +klass+.
        def part(key, klass) = parts[key.to_s] = klass

        # The folder of the hunt files (+nil+ for none); setting it starts a
        # new #book.
        attr_reader :directory

        # Sets #directory and forgets the old #book.
        def directory=(path)
          @directory = path&.to_s
          @book = nil
        end

        # The Book of #directory.
        def book = @book ||= Book.new(directory)

        # The time zone of the hunts' weeks; Rubbs::Common::Badges.time_zone.
        def time_zone = Badges.time_zone

        # +text+ as answers are compared: lower case, without accents, only
        # letters and digits ("256 mg" and "256MG" are alike).
        def normalize(text) = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]/, '')
      end

      part :find, Find
      part :answer, Answer
    end
  end
end
