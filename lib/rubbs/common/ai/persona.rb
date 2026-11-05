# frozen_string_literal: true

module Rubbs
  module Common
    module AI
      # Who the model plays, as data. The YAML file:
      #
      #   system: |                 # the system prompt; line breaks are kept
      #     You are …
      #   examples:                 # turns in the right voice, sent before the history
      #     - user: hi
      #       assistant: I am here.
      #   options:                  # extra request fields (sampling), optional
      #     temperature: 0.8
      #     max_tokens: 96
      #   deflect:                  # answered without the model, tried first:
      #     - match: '\b(code|python)\b'   # what a small model gets wrong
      #       reply: I do not write code.
      #   fallback:                 # canned replies, tried top to bottom
      #     replies:
      #       - match: '\b(hello|hi)\b'   # a case-insensitive regexp
      #         reply: I am here.
      #     default: 'You said: "{input}".'
      class Persona
        # The system prompt String (stripped), the example turns as an Array of
        # chat messages (<tt>{ role:, content: }</tt> Hashes, user and
        # assistant in turn), and the extra request fields as a Hash with
        # Symbol keys. All three are frozen or read-only data.
        attr_reader :system, :examples, :options

        # Reads the YAML file at +path+ and returns a Persona built from its
        # +system+, +examples+, +options+, +deflect+ and +fallback+ keys; other
        # keys are ignored. Raises the usual file and Psych errors for a
        # missing or invalid file.
        def self.load(path)
          data = YAML.safe_load_file(path, aliases: false) || {}
          new(**data.transform_keys(&:to_sym).slice(:system, :examples, :options, :deflect, :fallback))
        end

        # Creates a persona from the parts of the YAML file (see the class
        # description), with String keys inside +examples+, +deflect+ and
        # +fallback+ as YAML gives them.
        #
        # [system]   the system prompt
        # [examples] Array of <tt>{'user' => ..., 'assistant' => ...}</tt> turns
        # [options]  extra fields for every request, such as +temperature+
        # [deflect]  Array of <tt>{'match' => regexp, 'reply' => text}</tt> rules
        #            answered without the model
        # [fallback] Hash with +replies+ (rules as for +deflect+) and +default+
        #
        # Raises KeyError when an example or rule lacks a key, RegexpError for
        # an invalid +match+.
        def initialize(system: '', examples: [], options: {}, deflect: [], fallback: {})
          @system   = system.to_s.strip
          @examples = turns(examples)
          @options  = (options || {}).transform_keys(&:to_sym).freeze
          fallback ||= {}
          @deflect  = rules(deflect)
          @replies  = rules(fallback['replies'])
          @default  = fallback['default'].to_s.strip
        end

        # Returns the reply for +text+ that needs no model, or +nil+ when no
        # deflect rule matches: for questions a small model answers out of
        # character. <tt>{input}</tt> in the reply is replaced by +text+.
        def deflect(text)
          _, reply = @deflect.find { |pattern, _| pattern.match?(text) }
          reply&.gsub('{input}') { text }
        end

        # Returns the canned reply for +text+: that of the first matching
        # fallback rule, else the default (an empty String when the persona has
        # none). <tt>{input}</tt> in the reply is replaced by +text+.
        def fallback(text)
          _, reply = @replies.find { |pattern, _| pattern.match?(text) }
          (reply || @default).gsub('{input}') { text }
        end

        # Returns the messages that open every request: the system prompt (left
        # out when empty) followed by the example turns. +facts+ (a String) is
        # added to the system prompt for this one request: what the character
        # should know right now, such as something looked up for the question
        # at hand.
        def messages(facts = nil)
          system = [@system, facts.to_s.strip].reject(&:empty?).join("\n\n")
          [({ role: 'system', content: system } unless system.empty?), *@examples].compact
        end

        private

        def turns(examples)
          Array(examples).flat_map do |turn|
            [{ role: 'user', content: turn.fetch('user').to_s.strip },
             { role: 'assistant', content: turn.fetch('assistant').to_s.strip }]
          end.freeze
        end

        def rules(list)
          Array(list).map do |rule|
            [Regexp.new(rule.fetch('match'), Regexp::IGNORECASE), rule.fetch('reply').to_s.strip]
          end.freeze
        end
      end
    end
  end
end
