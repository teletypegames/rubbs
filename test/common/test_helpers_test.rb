# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

class TestHelpersTest < Minitest::Test
  def teardown = Rubbs.config.auth_secrets = []

  def test_tmp_data_goes_with_the_block
    kept = Rubbs::Test.tmp_data do |dir|
      File.write(File.join(dir, 'a.txt'), 'x')
      assert File.directory?(dir)
      dir
    end
    refute File.exist?(kept)
  end

  def test_stub_http_answers_from_the_routes_and_puts_the_real_one_back
    real = Rubbs::Common::Web::HTTP.method(:get)
    routes = {
      '/api/boards'             => { boards: ['alexandria'] },
      %r{/feed}                 => [503, 'down'],
      'https://x.org/plain?q=1' => 'hello',
      '/broken'                 => Rubbs::Common::Web::HTTP::Error,
      '/echo'                   => ->(url, **options) { [201, "#{url} #{options[:body]}"] }
    }
    Rubbs::Test.stub_http(routes) do |asked|
      http = Rubbs::Common::Web::HTTP
      assert_equal({ 'boards' => ['alexandria'] }, JSON.parse(http.get('https://x.org/api/boards').body))
      assert_equal([503, 'down'], http.get('https://x.org/feed.xml').then { |r| [r.status, r.body] })
      assert_equal 'hello', http.get('https://x.org/plain?q=1').body
      assert_raises(Rubbs::Common::Web::HTTP::Error) { http.get('https://x.org/broken') }
      assert_raises(Rubbs::Common::Web::HTTP::Error) { http.get('https://x.org/nowhere') }
      assert_equal([201, 'https://x.org/echo a=1'], http.post('https://x.org/echo', body: 'a=1').then { |r| [r.status, r.body] })
      assert_equal 6, asked.size
      assert_equal :post, asked.last.first
    end
    assert_equal real, Rubbs::Common::Web::HTTP.method(:get)
  end

  def test_screen_text_drops_the_escapes_of_a_modern_line
    line = Rubbs::Test::Session.new
    line.write("\e[2J\e[1;1H\e[1;33mWelcome,\e[0m\r\n   Ada.\e]0;title\a")
    assert_equal 'Welcome, Ada.', Rubbs::Test.screen_text(line)
  end

  def test_screen_text_of_a_c64_line_is_its_screen
    line = Rubbs::Test::Session.new(petscii: true)
    line.write("\x93HELLO")
    assert_includes Rubbs::Test.screen_text(line), 'HELLO'
  end

  def test_a_token_is_taken_by_the_board_as_a_login_elsewhere
    key = Rubbs::Test.token('Ada', roles: %w[member])
    line = Rubbs::Test::Session.new(forwarded: { 'RUBBS_AUTH_KEY' => key, 'BBS_VIA' => 'ttg-gate-bbs' })
    identity = nil
    capture_io { identity = Rubbs::Common::Auth.from_line(line) }
    assert_equal ['Ada', ['member'], :token], [identity.name, identity.roles, identity.source]
  end
end
