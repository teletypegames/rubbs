# frozen_string_literal: true

require_relative 'media_wiki'

module BBS
  # Wikipedia's Action API as a board asks it: a BBS::MediaWiki whose every
  # call names the language, all languages sharing one pace.
  #
  #   WIKIPEDIA = BBS::Wikipedia.new(user_agent: 'Alexandria BBS (+https://teletypegames.org)')
  #   WIKIPEDIA.get('en', action: 'query', list: 'random', rnnamespace: 0, rnlimit: 1)
  #   # => { "batchcomplete" => true, "query" => { "random" => [...] } }
  class Wikipedia < MediaWiki
    # Raised when Wikipedia does not answer, answers an error status or no
    # JSON, or the request found no turn; a BBS::MediaWiki::Error.
    class Error < MediaWiki::Error; end

    # Creates a client that sends +user_agent+, at most +rate+ requests a
    # second, each waiting at most +max_wait+ seconds for its turn.
    def initialize(user_agent:, rate: RATE, max_wait: MAX_WAIT)
      super(endpoint: nil, user_agent: user_agent, name: 'Wikipedia', rate: rate, max_wait: max_wait)
    end

    # Returns the answer of the Action API to +params+ on the +lang+
    # Wikipedia (+format=json+, +formatversion=2+), parsed: a Hash. Raises
    # Error.
    def get(lang, **params)
      request("https://#{URI.encode_www_form_component(lang)}.wikipedia.org/w/api.php", params)
    end
  end
end
