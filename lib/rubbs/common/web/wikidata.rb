# frozen_string_literal: true

require 'json'
require 'uri'

module Rubbs
  module Common
    module Web
      # Wikidata's SPARQL endpoint (its data is CC0) as a board's import asks
      # it: a POST through Rubbs::Common::Web::HTTP with long timeouts and a large body cap,
      # one query at a time with a pause before each, so a refresh of a catalog
      # does not hammer the service.
      #
      #   WIKIDATA = Rubbs::Common::Web::Wikidata.new(user_agent: 'Starbase BBS (+https://teletypegames.org)')
      #   WIKIDATA.select('SELECT ?item WHERE { ?item wdt:P31 wd:Q61220733 }').map { |row| Rubbs::Common::Web::Wikidata.qid(row['item']) }
      #   # => ["Q1129342", ...]
      class Wikidata
        # Raised when Wikidata answers an error status or no JSON; a
        # Rubbs::Common::Web::HTTP::Error.
        class Error < HTTP::Error; end

        # The public SPARQL endpoint.
        ENDPOINT = 'https://query.wikidata.org/sparql'
        # Seconds to wait for the connection.
        OPEN_TIMEOUT = 10
        # Seconds to wait for each read.
        READ_TIMEOUT = 90
        # Seconds a whole query may take.
        DEADLINE = 180
        # The largest answer read, in bytes.
        MAX_BYTES = 32 * 1024 * 1024

        # Creates a client that sends +user_agent+ (Wikidata asks for a
        # contact in it) to +endpoint+, sleeping +pause+ seconds before each
        # query.
        def initialize(user_agent:, endpoint: ENDPOINT, pause: 1)
          @user_agent = user_agent
          @endpoint   = endpoint
          @pause      = pause
        end

        # The rows of the SPARQL +query+'s answer: an Array of Hashes, by
        # variable, of the bindings (<tt>{ "value" => …, "type" => … }</tt>).
        # Raises Error, or Rubbs::Common::Web::HTTP::Error when the service does not answer.
        def select(query)
          sleep @pause
          response = HTTP.post(
            @endpoint,
            body:         URI.encode_www_form(query: query),
            user_agent:   @user_agent,
            headers:      {
              'Accept'       => 'application/sparql-results+json',
              'Content-Type' => 'application/x-www-form-urlencoded'
            },
            open_timeout: OPEN_TIMEOUT,
            read_timeout: READ_TIMEOUT,
            deadline:     DEADLINE,
            max_bytes:    MAX_BYTES
          )
          raise Error, "Wikidata answered #{response.status}" unless response.ok?

          JSON.parse(Text.utf8(response.body)).dig('results', 'bindings') || []
        rescue JSON::ParserError => e
          raise Error, "Wikidata answered no JSON: #{e.message[0, 80]}"
        end

        # The item id (<tt>Q42</tt>) of an entity +binding+ of a row, nil for
        # anything else.
        def self.qid(binding) = binding&.dig('value').to_s[%r{/entity/(Q\d+)\z}, 1]

        # The value of a +binding+ as one clean line (Rubbs::Common::Text.line); empty
        # for none.
        def self.text(binding) = Text.line(binding&.dig('value'))
      end
    end
  end
end
