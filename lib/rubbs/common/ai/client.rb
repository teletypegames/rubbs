# frozen_string_literal: true

module Rubbs
  module Common
    module AI
      # A streaming client for an OpenAI-compatible
      # <tt>/v1/chat/completions</tt> endpoint. At most
      # <tt>Rubbs.config.ai_concurrency</tt> requests run at once in the
      # process (see SLOTS).
      class Client
        # One complete line at the start of the stream buffer, with its LF.
        STREAM_LINE = /\A[^\n]*\n/
        # Seconds one request may take altogether, by default.
        DEADLINE = 120
        # The most bytes of reply text taken from one request, by default.
        MAX_REPLY = 65_536
        # The most bytes of the stream kept while waiting for a line end.
        MAX_LINE = 65_536
        # Seconds a request waits for its turn when the model is busy.
        QUEUE_WAIT = 5

        # The base URL of the server, as a String; empty when no model is set
        # up.
        attr_reader :url

        # Creates a client for the server at +url+ (its path is replaced by
        # <tt>/v1/chat/completions</tt>).
        #
        # [model]        sent as the request's +model+ field when given
        # [api_key]      sent as a Bearer token when given
        # [open_timeout] seconds to wait for the connection
        # [read_timeout] seconds to wait for each read of the reply
        # [deadline]     seconds the whole request may take
        # [max_bytes]    the most bytes of reply text taken
        def initialize(
          url:,
          model: nil,
          api_key: nil,
          open_timeout: 2,
          read_timeout: 30,
          deadline: DEADLINE,
          max_bytes: MAX_REPLY
        )
          @url          = url.to_s
          @model        = model
          @api_key      = api_key
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @deadline     = deadline
          @max_bytes    = max_bytes
        end

        # Returns whether a URL is set, so the client can be asked at all.
        def enabled? = !@url.empty?

        # Posts a streaming chat request with +messages+ (an Array of
        # <tt>{ role:, content: }</tt> Hashes) and +options+ merged into the
        # request body, and yields each piece of the reply's text as it
        # arrives. Raises RuntimeError (<tt>"HTTP 503"</tt> and the like) for a non-2xx
        # answer, Busy when the model is taken (see SLOTS), Error when the
        # request outlives its +deadline+, the reply passes +max_bytes+ or a
        # stream line MAX_LINE, and the Net::HTTP, socket, timeout and JSON
        # errors as they come.
        def stream(messages, **options, &)
          SLOTS.hold(limit: Rubbs.config.ai_concurrency, wait: QUEUE_WAIT) { request(messages, options, &) }
        end

        private

        def request(messages, options, &block)
          uri  = URI.join(@url, '/v1/chat/completions')
          body = { messages: messages, stream: true, **options }
          body[:model] = @model if @model
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl:      uri.scheme == 'https',
            open_timeout: @open_timeout,
            read_timeout: @read_timeout
          ) do |http|
            http.request(build_request(uri, body)) do |response|
              raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

              read_reply(response, &block)
            end
          end
        end

        def read_reply(response)
          taken = 0
          each_event(response, AI.monotonic + @deadline) do |event|
            piece = event.dig('choices', 0, 'delta', 'content') or next
            taken += piece.bytesize
            raise Error, 'the reply is too long' if taken > @max_bytes

            yield piece
          end
        end

        def build_request(uri, body)
          request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
          request['Authorization'] = "Bearer #{@api_key}" if @api_key
          request.body = JSON.generate(body)
          request
        end

        # Yields each parsed JSON event of a server-sent event stream: one
        # <tt>data: {json}</tt> line per chunk, <tt>[DONE]</tt> at the end.
        def each_event(response, deadline)
          buffer = +''
          response.read_body do |chunk|
            raise Error, 'the model took too long' if AI.monotonic > deadline

            buffer << chunk
            while (line = buffer.slice!(STREAM_LINE))
              next if line.start_with?(':')

              data = line.strip.delete_prefix('data:').strip
              next if data.empty? || data == '[DONE]'

              yield JSON.parse(data)
            end
            raise Error, 'a stream line is too long' if buffer.bytesize > MAX_LINE
          end
        end
      end
    end
  end
end
