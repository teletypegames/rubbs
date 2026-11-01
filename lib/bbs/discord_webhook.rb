# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module BBS
  # Posts messages to a Discord channel through its webhook URL. Plain Ruby
  # with no other part of the gem, so a board's domain can use it without
  # the telnet server:
  #
  #   require 'bbs/discord_webhook'
  #
  #   discord = BBS::DiscordWebhook.new(ENV['DISCORD_WEBHOOK'], label: 'feedia: Discord')
  #   discord.post("📨 **#{BBS::DiscordWebhook.escape(name)}** wrote to the admins")
  #
  # A post goes out in a thread of its own, so a slow webhook never stalls
  # a call. Mentions are off (a caller cannot ping @everyone), the content
  # is cut at +max+ characters, and at most +relay_max+ posts go out in
  # +relay_window+ seconds, however many callers post, so a crowd cannot
  # flood the channel: the rest are dropped with a warning. Errors and
  # answers other than 2xx are warned (Kernel#warn), never raised. Without
  # a URL (+nil+ or empty) it is off and posts nothing.
  class DiscordWebhook
    # The default most characters of a post's content (Discord takes 2000).
    MAX = 1500
    # The default most posts in a RELAY_WINDOW.
    RELAY_MAX = 20
    # The default window of the relay limit, in seconds.
    RELAY_WINDOW = 600
    # The default seconds to wait for the connection and for each read and
    # write.
    TIMEOUT = 10
    # The message flag that turns off the link previews (embeds).
    SUPPRESS_EMBEDS = 4
    # The characters of Discord's markdown (and @), which ::escape escapes.
    MARKDOWN = /([\\*_~`|>\[\]()<#:@-])/

    # +text+ with Discord's markdown characters (and @, links included)
    # backslash-escaped, so a caller's text shows as typed.
    def self.escape(text) = text.to_s.gsub(MARKDOWN) { "\\#{Regexp.last_match(1)}" }

    # +text+ on one line (runs of whitespace one space, stripped), cut to
    # +limit+ characters with an ellipsis after. Not escaped.
    def self.clip(text, limit)
      flat = text.to_s.gsub(/\s+/, ' ').strip
      flat.length > limit ? "#{flat[0, limit]}…" : flat
    end

    # The webhook's URI, or +nil+ when it is off.
    attr_reader :uri

    # Creates a webhook client for +url+ (a String or URI; +nil+ or empty:
    # off).
    #
    # [max]          the most characters of a post's content
    # [relay_max]    the most posts in +relay_window+ seconds; +nil+ for no
    #                limit
    # [relay_window] the window of the relay limit, in seconds
    # [embeds]       false to post with SUPPRESS_EMBEDS: no link previews
    # [timeout]      seconds to wait for the connection, and for each read
    #                and write
    # [label]        what the warnings start with
    def initialize(url, max: MAX, relay_max: RELAY_MAX, relay_window: RELAY_WINDOW, embeds: true,
                   timeout: TIMEOUT, label: 'Discord')
      @uri          = url.to_s.empty? ? nil : URI(url.to_s)
      @max          = max
      @relay_max    = relay_max
      @relay_window = relay_window
      @embeds       = embeds
      @timeout      = timeout
      @label        = label
      @sent         = []
      @mutex        = Mutex.new
    end

    # Whether it has a URL to post to.
    def enabled? = !@uri.nil?

    # Posts +content+ (cut at +max+) in a background thread, mentions off.
    # Thread-safe.
    #
    # Returns the Thread (join it to wait for the post), or +nil+ when the
    # webhook is off or the relay limit is reached (warned).
    def post(content)
      return unless enabled?
      return warn("#{@label}: relay limit reached, not sent") unless relay_slot?

      body = { content: content.to_s[0, @max], allowed_mentions: { parse: [] } }
      body[:flags] = SUPPRESS_EMBEDS unless @embeds
      payload = JSON.generate(body)
      Thread.new { deliver(payload) }
    end

    private

    # True when one more post fits in the window, and counts it.
    def relay_slot?
      return true if @relay_max.nil?

      @mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @sent.shift while @sent.any? && now - @sent.first > @relay_window
        next false if @sent.size >= @relay_max

        @sent << now
        true
      end
    end

    def deliver(payload)
      Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https', open_timeout: @timeout,
                                            read_timeout: @timeout, write_timeout: @timeout) do |http|
        request = Net::HTTP::Post.new(@uri, 'Content-Type' => 'application/json')
        request.body = payload
        response = http.request(request)
        warn "#{@label} error: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      end
    rescue StandardError => e
      warn "#{@label} error: #{e}"
    end
  end
end
