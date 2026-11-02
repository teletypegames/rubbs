# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'yaml'

module BBS
  # A conversational character for a BBS: a persona read from a YAML file, a
  # small model behind any OpenAI-compatible chat endpoint (llama.cpp's
  # llama-server, Ollama, vLLM, a hosted API, …), a short per-caller memory,
  # and canned replies for when the model is missing or fails.
  #
  #   PERSONA = BBS::AI::Persona.load('lib/oracle.yml')
  #   ORACLE  = BBS::AI::Chat.new(
  #     persona: PERSONA,
  #     client:  BBS::AI::Client.new(url: ENV.fetch('ORACLE_LLM_URL', ''))
  #   )
  #
  #   on_unknown do |input, io|
  #     out = BBS::AI::Typewriter.new(io, prefix: 'ORACLE: ', style: :dim)
  #     ORACLE.reply(input, io.ctx) { |piece| out.write(piece) }
  #     out.finish
  #   end
  #
  # With an empty URL the chat never calls a model and answers from the
  # persona's canned replies only, so a BBS can ship the character before it
  # has a model to run.
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

    # Raised by Client when a request cannot be made or goes wrong in a way
    # of its own (the network and HTTP errors come as they are).
    class Error < StandardError; end

    # Raised by Client#stream when <tt>BBS.config.ai_concurrency</tt>
    # requests are running and none ended within Client::QUEUE_WAIT
    # seconds. Its message can be shown to the caller.
    class Busy < Error; end

    # A counting semaphore: at most a given number of holders at once, the
    # others wait their turn for a while.
    class Semaphore
      # Creates a semaphore nobody holds.
      def initialize
        @mu    = Mutex.new
        @freed = ConditionVariable.new
        @held  = 0
      end

      # Runs the block once fewer than +limit+ hold the semaphore, waiting
      # up to +wait+ seconds for that. Returns the block's value; raises Busy
      # when the wait runs out.
      def hold(limit:, wait:)
        raise Busy, 'The model is busy, try again in a moment.' unless take(limit, wait)

        begin
          yield
        ensure
          give
        end
      end

      private

      def take(limit, wait)
        deadline = AI.monotonic + wait
        @mu.synchronize do
          while @held >= limit
            left = deadline - AI.monotonic
            return false unless left.positive?

            @freed.wait(@mu, left)
          end
          @held += 1
        end
      end

      def give
        @mu.synchronize do
          @held -= 1
          @freed.signal
        end
      end
    end

    # The one Semaphore of the process that every Client request holds.
    SLOTS = Semaphore.new

    # Returns the seconds of the monotonic clock.
    def self.monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # A streaming client for an OpenAI-compatible
    # <tt>/v1/chat/completions</tt> endpoint. At most
    # <tt>BBS.config.ai_concurrency</tt> requests run at once in the
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
      def initialize(url:, model: nil, api_key: nil, open_timeout: 2, read_timeout: 30,
                     deadline: DEADLINE, max_bytes: MAX_REPLY)
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
        SLOTS.hold(limit: BBS.config.ai_concurrency, wait: QUEUE_WAIT) { request(messages, options, &) }
      end

      private

      def request(messages, options, &block)
        uri  = URI.join(@url, '/v1/chat/completions')
        body = { messages: messages, stream: true, **options }
        body[:model] = @model if @model
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
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

    # A persona talking through a client, with a short memory per caller.
    class Chat
      # The default reply filter: what a plain-text terminal cannot show,
      # Markdown marks and emoji.
      PLAIN_TEXT = /[*#`\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]/

      # Creates a chat for +persona+ (a Persona) answering through +client+
      # (a Client).
      #
      # [history] how many past messages (user and assistant) to send along
      # [key]     where in the caller's context Hash the history is kept
      # [filter]  a Regexp of characters removed from the reply, +nil+ to
      #           keep everything
      # [options] request fields that override the persona's +options+
      def initialize(persona:, client:, history: 6, key: :ai_history, filter: PLAIN_TEXT, options: {})
        @persona = persona
        @client  = client
        @history = history
        @key     = key
        @filter  = filter
        @options = persona.options.merge(options)
      end

      # Returns the reply to the caller's +text+. A deflect rule of the
      # persona answers first; otherwise the model is asked (when the client
      # is enabled) with the persona's messages, the caller's history from
      # +ctx+ and +text+; when that gives nothing, the fallback answers. With
      # a block, the reply is also yielded piece by piece as it arrives, so
      # the terminal can type it out live; a canned reply is yielded whole.
      #
      # A model reply is added to the history in +ctx+ (a Hash; anything else
      # keeps no history), which is cut to the last +history+ messages. A
      # model error is reported on stderr, and a reply cut short by it is
      # kept as it is.
      #
      # [facts]    added to the system prompt for this request only (not kept
      #            in the history), see Persona#messages
      # [fallback] the reply when the model is missing or fails, instead of
      #            the persona's canned one, such as the looked-up facts as
      #            they are
      def reply(text, ctx = {}, facts: nil, fallback: nil, &on_text)
        text = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub('').strip
        if (canned = @persona.deflect(text))
          return canned.tap { |line| on_text&.call(line) }
        end

        reply = (think(text, ctx, facts, &on_text) if @client.enabled?)
        return reply if reply

        (fallback || @persona.fallback(text)).tap { |line| on_text&.call(line) }
      end

      private

      # nil when the model gave nothing, so the caller falls back; a reply
      # cut short mid-way is kept as it is.
      def think(text, ctx, facts, &)
        history = ctx.is_a?(Hash) ? (ctx[@key] ||= []) : []
        reply   = +''
        listen([*@persona.messages(facts), *history, { role: 'user', content: text }], reply, &)
        remember(history, text, reply.strip)
      rescue StandardError => e
        BBS.log('ai', "model unavailable (#{e.class}: #{e.message})")
        reply.to_s.strip.empty? ? nil : reply.strip
      end

      # Streams the model's answer to +messages+ into +reply+, filtered,
      # each piece also to +on_text+.
      def listen(messages, reply, &on_text)
        @client.stream(messages, **@options) do |piece|
          piece = piece.gsub(@filter, '') if @filter
          next if piece.empty?

          reply << piece
          on_text&.call(piece)
        end
      end

      def remember(history, text, reply)
        return nil if reply.nil? || reply.empty?

        history.push({ role: 'user', content: text }, { role: 'assistant', content: reply })
        history.shift(history.size - @history) if history.size > @history
        reply
      end
    end

    # Types streamed text onto a FakeOS console, word-wrapped to the caller's
    # terminal under a prefix:
    #
    #   ACP: The bus is quiet tonight, and I am
    #        listening to it.
    #
    # Words are held back until they are whole, and whitespace is written only
    # before the next word, so a reply never ends on a dangling blank line.
    class Typewriter
      # Creates a typewriter on +io+ (a FakeOS console) and prints +prefix+.
      #
      # [prefix] printed once; wrapped lines are indented by its length
      # [style]  the FakeOS style the text is printed in
      # [width]  the line width, by default one less than the terminal's;
      #          at least 20 columns are left for the text
      def initialize(io, prefix: '', style: :text, width: nil)
        @io      = io
        @style   = style
        @indent  = ' ' * prefix.size
        @width   = [(width || (io.cols - 1)) - prefix.size, 20].max
        @col     = 0
        @gap     = nil
        @pending = +''
        @io.print prefix, style: @style, newline: 0
      end

      # Adds +piece+ of the streamed text, printing every word it completes
      # and keeping the unfinished one back.
      def write(piece)
        @pending << piece
        while (m = @pending.match(Text::WHITESPACE))
          word(m.pre_match)
          @gap = "#{@gap}#{m[0]}"
          @pending = m.post_match
        end
      end

      # Writes the last word and +newlines+ line breaks.
      def finish(newlines: 2)
        word(@pending)
        @pending = +''
        @io.newline(newlines)
      end

      private

      def word(text)
        return if text.empty?

        space_before(text) if @col.positive?
        out(text)
        @col += text.size
        @gap = nil
      end

      # A line break before +text+ when the gap had one or the line is full,
      # else one space when there was a gap.
      def space_before(text)
        if @gap&.include?("\n") || @col + 1 + text.size > @width
          out("#{Ansi::CRLF}#{@indent}")
          @col = 0
        elsif @gap
          out(' ')
          @col += 1
        end
      end

      def out(text) = @io.print(text, style: @style, newline: 0)
    end
  end
end
