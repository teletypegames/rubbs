# frozen_string_literal: true

require 'json'
require 'uri'

module BBS
  # Wikipedia's Action API as a board asks it: a GET through BBS::HTTP that
  # names the board in its User-Agent (Wikipedia may answer 403 without
  # one), paced by a BBS::RateLimit so that all callers together send at
  # most +rate+ requests a second. A request that would wait longer than
  # +max_wait+ seconds for its turn is not sent, so a crowd on the board
  # cannot get its address throttled there.
  #
  #   WIKIPEDIA = BBS::Wikipedia.new(user_agent: 'Alexandria BBS (+https://teletypegames.org)')
  #   WIKIPEDIA.get('en', action: 'query', list: 'random', rnnamespace: 0, rnlimit: 1)
  #   # => { "batchcomplete" => true, "query" => { "random" => [...] } }
  class Wikipedia
    # Raised when Wikipedia does not answer, answers an error status or no
    # JSON, or the request found no turn; a BBS::HTTP::Error, so a
    # repository that rescues those rescues this one too.
    class Error < HTTP::Error; end

    # Requests a second, all callers together, by default.
    RATE = 5
    # Seconds a request waits for its turn at most, by default.
    MAX_WAIT = 3

    # Creates a client that sends +user_agent+, at most +rate+ requests a
    # second, each waiting at most +max_wait+ seconds for its turn.
    def initialize(user_agent:, rate: RATE, max_wait: MAX_WAIT)
      @user_agent = user_agent
      @pace       = RateLimit.new(limit: rate, per: 1)
      @max_wait   = max_wait
    end

    # Returns the answer of the Action API to +params+ on the +lang+
    # Wikipedia (+format=json+, +formatversion=2+), parsed: a Hash. Raises
    # Error.
    def get(lang, **params)
      raise Error, 'busy: too many Wikipedia requests at once' unless turn?

      response = HTTP.get(url(lang, params), user_agent: @user_agent, headers: { 'Accept-Encoding' => 'identity' })
      raise Error, "Wikipedia answered #{response.status}" unless response.ok?

      JSON.parse(Text.utf8(response.body))
    rescue JSON::ParserError => e
      raise Error, "Wikipedia answered no JSON: #{e.message[0, 80]}"
    end

    private

    def url(lang, params)
      query = URI.encode_www_form(params.merge(format: 'json', formatversion: 2))
      "https://#{URI.encode_www_form_component(lang)}.wikipedia.org/w/api.php?#{query}"
    end

    # Waits for a turn; false when none comes within +max_wait+.
    def turn?
      deadline = monotonic + @max_wait
      until @pace.allow?(:wikipedia)
        wait = @pace.wait(:wikipedia)
        return false if monotonic + wait > deadline

        sleep wait
      end
      true
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
