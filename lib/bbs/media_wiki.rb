# frozen_string_literal: true

require 'json'
require 'uri'

module BBS
  # The Action API of a MediaWiki site (Wikipedia, Memory Alpha, any
  # <tt>api.php</tt>) as a board asks it: a GET through BBS::HTTP that names
  # the board in its User-Agent (a wiki may answer 403 without one), paced
  # by a BBS::RateLimit so that all callers together send at most +rate+
  # requests a second. A request that would wait longer than +max_wait+
  # seconds for its turn is not sent, so a crowd on the board cannot get
  # its address throttled there.
  #
  #   ALPHA = BBS::MediaWiki.new(endpoint: 'https://memory-alpha.fandom.com/api.php', name: 'Memory Alpha',
  #                              user_agent: 'Starbase BBS (+https://teletypegames.org)')
  #   ALPHA.get(action: 'query', list: 'search', srsearch: 'tribbles')
  #   # => { "query" => { "search" => [...] } }
  #
  # BBS::Wikipedia is one, with the language in every call; MediaWiki::Extract
  # cuts a plain-text extract into sections.
  class MediaWiki
    # Raised when the wiki does not answer, answers an error status or no
    # JSON, or the request found no turn; a BBS::HTTP::Error, so a
    # repository that rescues those rescues this one too.
    class Error < HTTP::Error; end

    # Requests a second, all callers together, by default.
    RATE = 5
    # Seconds a request waits for its turn at most, by default.
    MAX_WAIT = 3

    # The <tt>api.php</tt> address the requests go to.
    attr_reader :endpoint
    # The wiki's name in error messages.
    attr_reader :name

    # Creates a client of the Action API at +endpoint+ (the full address of
    # its <tt>api.php</tt>) that sends +user_agent+, at most +rate+ requests
    # a second, each waiting at most +max_wait+ seconds for its turn; +name+
    # is the wiki's name in error messages.
    def initialize(endpoint:, user_agent:, name: 'The wiki', rate: RATE, max_wait: MAX_WAIT)
      @endpoint   = endpoint
      @name       = name
      @user_agent = user_agent
      @pace       = RateLimit.new(limit: rate, per: 1)
      @max_wait   = max_wait
    end

    # Returns the answer of the Action API to +params+
    # (+format=json+, +formatversion=2+), parsed: a Hash. Raises Error.
    def get(**params) = request(@endpoint, params)

    private

    def request(endpoint, params)
      raise self.class::Error, "busy: too many #{@name} requests at once" unless turn?

      response = HTTP.get(address(endpoint, params), user_agent: @user_agent,
                                                     headers: { 'Accept-Encoding' => 'identity' })
      raise self.class::Error, "#{@name} answered #{response.status}" unless response.ok?

      JSON.parse(Text.utf8(response.body))
    rescue JSON::ParserError => e
      raise self.class::Error, "#{@name} answered no JSON: #{e.message[0, 80]}"
    end

    def address(endpoint, params)
      "#{endpoint}?#{URI.encode_www_form(params.merge(format: 'json', formatversion: 2))}"
    end

    # Waits for a turn; false when none comes within +max_wait+.
    def turn?
      deadline = monotonic + @max_wait
      until @pace.allow?(:wiki)
        wait = @pace.wait(:wiki)
        return false if monotonic + wait > deadline

        sleep wait
      end
      true
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
