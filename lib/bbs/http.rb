# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'socket'
require 'uri'
require 'zlib'

module BBS
  # HTTP requests of a board to the services it shows (an encyclopedia, a
  # feed, a catalog), bounded so a slow or huge answer cannot hold a
  # caller's thread or fill the memory: a deadline for the whole request, a
  # cap on the body, a few redirects to http and https only, and by default
  # no request to an address that is not on the public internet.
  #
  #   response = BBS::HTTP.get('https://en.wikipedia.org/w/api.php?action=query&format=json')
  #   JSON.parse(response.body) if response.ok?
  #
  # Every failure (no answer, a timeout, a body over the cap, a refused
  # address, a bad redirect) raises BBS::HTTP::Error, with a message that
  # names the address without its query string, so no key or search term
  # lands in a log. A body over the cap raises its subclass TooLarge, as
  # soon as the Content-Length says so.
  #
  # A big download goes to an IO instead of the memory:
  #
  #   File.open('book.txt', 'wb') { |file| BBS::HTTP.get(url, to: file, max_bytes: 64 * 1024 * 1024) }
  module HTTP
    # Raised when a request fails; see the module description.
    class Error < StandardError; end

    # Raised when the body is over the cap (+max_bytes+).
    class TooLarge < Error; end

    # The answer to a request.
    #
    # [status]  the HTTP status code, an Integer
    # [body]    the body, a binary String (+force_encoding+ it as needed)
    # [headers] the header fields, a Hash of lowercase name => value String
    #
    # The body is +nil+ when a 2xx body went to the +to+ IO of HTTP.get.
    Response = Struct.new(:status, :body, :headers, keyword_init: true) do
      # Returns whether the status is 2xx.
      def ok? = (200..299).cover?(status)
    end

    # The status codes of a redirect.
    REDIRECTS = [301, 302, 303, 307, 308].freeze
    # The URI schemes a request and its redirects may use.
    SCHEMES = %w[http https].freeze
    # The default cap on the body: 4 MiB.
    MAX_BYTES = 4 * 1024 * 1024
    # The errors of a request that become an Error.
    FAILURES = [SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
                Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error].freeze

    module_function

    # Sends a GET request to +url+ and returns its Response (a non-2xx one
    # too). Raises Error when it fails.
    #
    # [headers]      extra request header fields, a Hash
    # [open_timeout] seconds to wait for the connection
    # [read_timeout] seconds to wait for each read
    # [deadline]     seconds the whole request may take, redirects included
    # [max_bytes]    the most bytes of body read; more is a TooLarge
    # [to]           an IO the body of a 2xx answer is written to as it
    #                comes, instead of the Response's +body+ (+nil+ then);
    #                still capped by +max_bytes+, and a failure halfway
    #                leaves what came in the IO
    # [redirects]    the most redirects followed (to http or https only)
    # [user_agent]   the User-Agent field; default
    #                <tt>BBS.config.user_agent</tt>
    # [public_only]  refuse a host that is not on the public internet
    #                (BBS::Address.public?); the address checked is the one
    #                connected to, so a name cannot resolve twice
    def get(url, **) = Request.new(:get, url, **).run

    # Sends a POST request with +body+ (a String) to +url+, with the options
    # of #get; a redirect is not followed but returned. Returns the Response
    # and raises Error as #get does.
    #
    #   BBS::HTTP.post(SPARQL, body: URI.encode_www_form(query: q),
    #                  headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
    def post(url, body:, **) = Request.new(:post, url, body: body, redirects: 0, **).run

    # One request and its redirects; HTTP.get and HTTP.post make one.
    class Request
      # Prepares a request; the options are those of HTTP.get, +method+ is
      # +:get+ or +:post+ and +body+ the body of a POST.
      def initialize(method, url, body: nil, headers: {}, open_timeout: 5, read_timeout: 15, deadline: 30,
                     max_bytes: MAX_BYTES, redirects: 3, user_agent: BBS.config.user_agent, public_only: true, to: nil)
        @method      = method
        @url         = url.to_s
        @body        = body
        @headers     = { 'User-Agent' => user_agent, **headers }
        @timeouts    = [open_timeout, read_timeout]
        @max_bytes   = max_bytes
        @redirects   = redirects
        @public_only = public_only
        @to          = to
        @deadline    = monotonic + deadline
      end

      # Sends the request, follows its redirects and returns the last
      # Response. Raises Error when it fails.
      def run
        uri = address(@url)
        (@redirects + 1).times do
          response = exchange(uri)
          return response unless REDIRECTS.include?(response.status) && response.headers['location']

          uri = address(response.headers['location'], uri)
        end
        fail!(uri, 'too many redirects')
      end

      private

      def address(text, base = nil)
        uri = base ? base.merge(text) : URI(text)
        fail!(uri, 'not an http or https address') unless SCHEMES.include?(uri.scheme) && uri.host
        uri
      rescue URI::Error
        raise Error, 'not an http or https address'
      end

      def exchange(uri)
        http = connection(uri)
        http.start { http.request(request(uri)) { |response| return answer(uri, response) } }
      rescue *FAILURES => e
        fail!(uri, "#{e.class}: #{e.message}")
      end

      def connection(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.ipaddr       = ip(uri)
          http.use_ssl      = uri.scheme == 'https'
          http.open_timeout = left(uri, @timeouts[0])
          http.read_timeout = left(uri, @timeouts[1])
          http.write_timeout = left(uri, @timeouts[1])
          http.max_retries = 0
        end
      end

      def request(uri)
        (@method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri, @headers).tap do |request|
          request.body = @body if @body
        end
      end

      def answer(uri, response)
        status = response.code.to_i
        too_large!(uri) if response['content-length'].to_i > @max_bytes
        body = @to && (200..299).cover?(status) ? stream(uri, response) : read(uri, response)
        Response.new(status: status, body: body, headers: response.each_header.to_h)
      end

      def read(uri, response)
        body = +''.b
        each_chunk(uri, response) { |chunk| body << chunk }
        body
      end

      def stream(uri, response)
        each_chunk(uri, response) { |chunk| @to.write(chunk) }
        nil
      end

      # Yields the chunks of the body, within the cap and the deadline.
      def each_chunk(uri, response)
        bytes = 0
        response.read_body do |chunk|
          bytes += chunk.bytesize
          too_large!(uri) if bytes > @max_bytes
          left(uri, 1)
          yield chunk
        end
      end

      def too_large!(uri) = fail!(uri, "the body is over #{@max_bytes} bytes", TooLarge)

      # The address connected to, resolved once and checked.
      def ip(uri)
        ip = Addrinfo.getaddrinfo(uri.hostname, uri.port, nil, :STREAM).first&.ip_address
        fail!(uri, 'the host does not resolve') unless ip
        fail!(uri, "#{ip} is not a public address") if @public_only && !Address.public?(ip)
        ip
      end

      # The seconds left of the deadline, at most +limit+.
      def left(uri, limit)
        seconds = @deadline - monotonic
        fail!(uri, 'the deadline passed') unless seconds.positive?
        [seconds, limit].min
      end

      def fail!(uri, reason, error = Error)
        raise error, "#{@method.upcase} #{uri.scheme}://#{uri.host}#{uri.path}: #{reason}"
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
