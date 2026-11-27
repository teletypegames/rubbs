# frozen_string_literal: true

require 'json'

module Rubbs
  module Test
    # One escape sequence a modern line writes: CSI, OSC or a two-byte one.
    ESCAPE = %r{\e(?:\[[\d;?<>=]*[ -/]*[@-~]|\][^\a\e]*(?:\a|\e\\)?|[@-Z\\-_])}

    # A throwaway directory for a test's data files, removed when the block
    # ends; without a block, when the process does. Returns the block's
    # value, or the directory's path without one.
    #
    #   Rubbs::Test.tmp_data { |dir| Store.new(File.join(dir, 'wall.csv')) }
    #   def setup = @dir = Rubbs::Test.tmp_data
    def self.tmp_data(prefix = 'rubbs-test')
      dir = Dir.mktmpdir(prefix)
      return dir.tap { at_exit { FileUtils.rm_rf(dir) } } unless block_given?

      begin
        yield dir
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    # Runs the block with Rubbs::Common::Web::HTTP.get and .post answered
    # from +routes+ instead of the network, then puts them back. Yields the
    # requests asked so far, an Array of <tt>[method, url, options]</tt>
    # (the body of a POST among the options); returns the block's value.
    #
    # A route's key is a String (the whole URL, or its path with or without
    # the query) or a Regexp (matched against the whole URL); the first that
    # fits answers. The answer is
    #
    # * a String: a 200 with it as the body,
    # * a Hash or an Array of Hashes: a 200 with it as JSON,
    # * <tt>[status, body]</tt> or <tt>[status, body, headers]</tt> (a
    #   Hash or Array body as JSON),
    # * an Exception (class or instance): raised, as a failed request,
    # * anything that answers +call+: called with the url and the options,
    #   its value answered as above.
    #
    # A URL no route fits raises Rubbs::Common::Web::HTTP::Error.
    #
    #   Rubbs::Test.stub_http('/api/boards' => { boards: [] }, %r{/feed} => [503, '']) do |asked|
    #     board.refresh
    #     assert_equal 2, asked.size
    #   end
    def self.stub_http(routes = {}, &)
      HttpStub.new(routes).around(&)
    end

    # The words on a line's screen, for <tt>assert_includes</tt>: on a
    # PETSCII line (a Session with +petscii?+) the screen as it is now (a
    # Rubbs::Petscii::Canvas fed every byte written); otherwise everything
    # written with the escape sequences dropped and each run of white space
    # one space. +written+ is a Session or the String it wrote.
    #
    #   assert_includes Rubbs::Test.screen_text(session), 'Welcome, Ada.'
    def self.screen_text(written)
      if written.respond_to?(:petscii?) && written.petscii?
        Petscii::Canvas.new.feed(written.raw).to_s
      else
        text = written.respond_to?(:output) ? written.output : written.to_s.dup.force_encoding(Encoding::UTF_8)
        text.scrub('?').gsub(ESCAPE, '').gsub(/\s+/, ' ').strip
      end
    end

    # A RUBBS_AUTH_KEY the board +aud+ (its technical name, by default this
    # one's Rubbs.config.log_tag) takes as +who+ logged in elsewhere:
    # +who+ is a Rubbs::Common::Auth::Identity or a name (with +roles+ and
    # +id+). Sets the test secret (::auth_secret) when none is set.
    #
    #   key = Rubbs::Test.token('Ada', roles: %w[member])
    #   line = Rubbs::Test::Session.new(forwarded: { 'RUBBS_AUTH_KEY' => key, 'BBS_VIA' => 'ttg-gate-bbs' })
    def self.token(who, aud: Rubbs.config.log_tag, roles: [], id: nil)
      auth_secret if Array(Rubbs.config.auth_secrets).empty?
      Common::Auth::Token.issue(identity_of(who, roles, id), aud: aud)
    end

    # +who+ when it is a Rubbs::Common::Auth::Identity, else the signed-in
    # Identity named +who+ with +roles+ and +id+ (the name in lower case by default).
    def self.identity_of(who, roles = [], id = nil)
      return who if who.is_a?(Common::Auth::Identity)

      Common::Auth::Identity.new(id: id || who.to_s.downcase, name: who.to_s, roles: roles, source: :token)
    end

    # The answers of ::stub_http.
    class HttpStub
      # A stub answering from +routes+ (see Rubbs::Test.stub_http).
      def initialize(routes)
        @routes = routes
        @asked  = []
      end

      # Runs the block with HTTP.get and HTTP.post answered here; puts the
      # real ones back however it ends.
      def around
        http = Common::Web::HTTP
        real = %i[get post].to_h { |m| [m, http.method(m)] }
        stub = self
        http.define_singleton_method(:get) { |url, **options| stub.answer(:get, url, options) }
        http.define_singleton_method(:post) { |url, body:, **options| stub.answer(:post, url, options.merge(body: body)) }
        yield @asked
      ensure
        real&.each { |m, original| http.define_singleton_method(m, original) }
      end

      # The Rubbs::Common::Web::HTTP::Response for a +method+ request to +url+ with
      # +options+, noted in the requests asked.
      def answer(method, url, options)
        @asked << [method, url, options]
        _, value = @routes.find { |key, _| fits?(key, url) }
        raise Common::Web::HTTP::Error, "no stubbed answer for #{url}" if value.nil?

        response(value.respond_to?(:call) ? value.call(url, **options) : value)
      end

      private

      def fits?(key, url)
        return key.match?(url) if key.is_a?(Regexp)

        uri = URI(url)
        [url, uri.path, uri.request_uri].include?(key.to_s)
      end

      def response(value)
        raise value if value.is_a?(Exception) || (value.is_a?(Class) && value <= Exception)

        status, body, headers = value.is_a?(Array) && value.first.is_a?(Integer) ? value : [200, value]
        Common::Web::HTTP::Response.new(status: status, body: body_of(body), headers: headers || {})
      end

      def body_of(body) = (body.is_a?(String) ? body : JSON.generate(body)).b
    end
  end
end
