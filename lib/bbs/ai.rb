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
      attr_reader :system, :examples, :options

      def self.load(path)
        data = YAML.safe_load(File.read(path), aliases: false) || {}
        new(**data.transform_keys(&:to_sym).slice(:system, :examples, :options, :deflect, :fallback))
      end

      def initialize(system: '', examples: [], options: {}, deflect: [], fallback: {})
        @system   = system.to_s.strip
        @examples = Array(examples).flat_map do |turn|
          [{ role: 'user', content: turn.fetch('user').to_s.strip },
           { role: 'assistant', content: turn.fetch('assistant').to_s.strip }]
        end.freeze
        @options  = (options || {}).transform_keys(&:to_sym).freeze
        fallback  = fallback || {}
        @deflect  = rules(deflect)
        @replies  = rules(fallback['replies'])
        @default  = fallback['default'].to_s.strip
      end

      # The reply for `text` that needs no model, nil when no deflect rule
      # matches: questions a small model answers out of character.
      def deflect(text)
        _, reply = @deflect.find { |pattern, _| pattern.match?(text) }
        reply&.gsub('{input}', text)
      end

      # The canned reply for `text`: the first matching rule, else the default.
      def fallback(text)
        _, reply = @replies.find { |pattern, _| pattern.match?(text) }
        (reply || @default).gsub('{input}', text)
      end

      # `facts` (a String) is added to the system prompt for one request:
      # what the character should know right now, e.g. looked up for the
      # question at hand.
      def messages(facts = nil)
        system = [@system, facts.to_s.strip].reject(&:empty?).join("\n\n")
        [({ role: 'system', content: system } unless system.empty?), *@examples].compact
      end

      private

      def rules(list)
        Array(list).map do |rule|
          [Regexp.new(rule.fetch('match'), Regexp::IGNORECASE), rule.fetch('reply').to_s.strip]
        end.freeze
      end
    end

    # A streaming client for an OpenAI-compatible /v1/chat/completions.
    class Client
      attr_reader :url

      def initialize(url:, model: nil, api_key: nil, open_timeout: 2, read_timeout: 30)
        @url          = url.to_s
        @model        = model
        @api_key      = api_key
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def enabled? = !@url.empty?

      # Yields each piece of the reply's text as it arrives.
      def stream(messages, **options)
        uri  = URI.join(@url, '/v1/chat/completions')
        body = { messages: messages, stream: true, **options }
        body[:model] = @model if @model
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          http.request(build_request(uri, body)) do |response|
            raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            each_event(response) do |event|
              piece = event.dig('choices', 0, 'delta', 'content')
              yield piece if piece
            end
          end
        end
      end

      private

      def build_request(uri, body)
        request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        request['Authorization'] = "Bearer #{@api_key}" if @api_key
        request.body = JSON.generate(body)
        request
      end

      # Server-sent events: one `data: {json}` line per chunk, `[DONE]` at the end.
      def each_event(response)
        buffer = +''
        response.read_body do |chunk|
          buffer << chunk
          while (line = buffer.slice!(/\A[^\n]*\n/))
            next if line.start_with?(':')

            data = line.strip.delete_prefix('data:').strip
            next if data.empty? || data == '[DONE]'

            yield JSON.parse(data)
          end
        end
      end
    end

    # A persona talking through a client, with a short memory per caller.
    class Chat
      # What a plain-text terminal cannot show: markdown marks and emoji.
      PLAIN_TEXT = /[*#`\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]/

      # history: how many past messages (user and assistant) to send along;
      # key: where in the caller's context hash the history is kept;
      # filter: characters removed from the reply, nil to keep everything.
      def initialize(persona:, client:, history: 6, key: :ai_history, filter: PLAIN_TEXT, options: {})
        @persona = persona
        @client  = client
        @history = history
        @key     = key
        @filter  = filter
        @options = persona.options.merge(options)
      end

      # Returns the reply. With a block, the reply is also yielded piece by
      # piece as it arrives, so the terminal can type it out live. The canned
      # reply is yielded whole.
      #
      # facts:    added to the system prompt for this request only (not kept
      #           in the history), see Persona#messages;
      # fallback: the reply when the model is missing or fails, instead of
      #           the persona's canned one — e.g. the looked-up facts as they
      #           are.
      def reply(text, ctx = {}, facts: nil, fallback: nil, &on_text)
        text  = text.to_s.strip
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
      def think(text, ctx, facts, &on_text)
        history = ctx.is_a?(Hash) ? (ctx[@key] ||= []) : []
        reply   = +''
        @client.stream([*@persona.messages(facts), *history, { role: 'user', content: text }], **@options) do |piece|
          piece = piece.gsub(@filter, '') if @filter
          next if piece.empty?

          reply << piece
          on_text&.call(piece)
        end
        remember(history, text, reply.strip)
      rescue StandardError => e
        warn "BBS::AI: model unavailable (#{e.class}: #{e.message})"
        reply.to_s.strip.empty? ? nil : reply.strip
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
      def initialize(io, prefix: '', style: :text, width: nil)
        @io      = io
        @style   = style
        @indent  = ' ' * prefix.size
        @width   = [(width || io.cols - 1) - prefix.size, 20].max
        @col     = 0
        @gap     = nil
        @pending = +''
        @io.print prefix, style: @style, newline: 0
      end

      def write(piece)
        @pending << piece
        while (m = @pending.match(/\s+/))
          word(m.pre_match)
          @gap = "#{@gap}#{m[0]}"
          @pending = m.post_match
        end
      end

      # Writes the last word and `newlines` line breaks.
      def finish(newlines: 2)
        word(@pending)
        @pending = +''
        @io.newline(newlines)
      end

      private

      def word(text)
        return if text.empty?

        if @col.positive? && (@gap&.include?("\n") || @col + 1 + text.size > @width)
          out("\r\n#{@indent}")
          @col = 0
        elsif @col.positive? && @gap
          out(' ')
          @col += 1
        end
        out(text)
        @col += text.size
        @gap = nil
      end

      def out(text) = @io.print(text, style: @style, newline: 0)
    end
  end
end
