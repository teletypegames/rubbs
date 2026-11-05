# frozen_string_literal: true

module Rubbs
  module Common
    module AI
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
          Rubbs.log('ai', e, level: :warn)
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
    end
  end
end
