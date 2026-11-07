# frozen_string_literal: true

require 'test_helper'

# A wall: what a network adds to its Central.
class TestWall < Rubbs::Common::Central::Service
  path '/wall'
  database :test_wall, ['CREATE TABLE notes (id INTEGER PRIMARY KEY, name TEXT, text TEXT NOT NULL)']

  op(:post) do |actor, text:, **|
    next :empty if text.to_s.strip.empty?

    { id: database[:notes].insert(name: actor.name, text: text) }
  end

  op(:recent, actor: false) { |_, **| { notes: database[:notes].order(:id).select_map(%i[name text]) } }
  op(:who) { |actor, **| { name: actor.name, guest: actor.guest?, roles: actor.roles, asker: asker } }
  op(:wipe, role: :sysop) { |_, **| database[:notes].delete && :ok }
end

class CentralSignatureTest < Minitest::Test
  def setup = Rubbs::Test.auth_secret

  def teardown = Rubbs.config.auth_secrets = []

  def test_the_path_is_signed_too
    signature = Rubbs::Common::Central::Signature.sign('/wall', '{}')
    assert Rubbs::Common::Central::Signature.valid?('/wall', '{}', signature)
    refute Rubbs::Common::Central::Signature.valid?('/auth', '{}', signature)
    refute Rubbs::Common::Central::Signature.valid?('/wall', '{ }', signature)
  end

  def test_the_old_auth_signature_is_refused
    server = Rubbs::Common::Central::Server.new(services: [Rubbs::Common::Auth::Service], accounts: Rubbs::Test.accounts)
    body   = JSON.generate(op: 'known', name: 'ada', ts: Time.now.to_i)
    key    = Rubbs::Common::Auth::Token.keys('rubbs-auth v1 api').first[:key]
    old    = Rubbs::Common::Auth::Token.encode(Rubbs::Common::Auth::Token.sign(key, body))
    assert_equal({ 'error' => 'signature' }, server.answer('/auth', body, old))
    assert_equal({ 'result' => false }, server.answer('/auth', body, Rubbs::Common::Central::Signature.sign('/auth', body)))
  end
end

class CentralServerTest < Minitest::Test
  def setup
    Rubbs::Test.auth_secret
    @data     = Dir.mktmpdir('central')
    @accounts = Rubbs::Test.accounts(roles: ['member'])
    @ada      = @accounts.register('Ada', 'secret1')
    @server   = Rubbs::Common::Central::Server.new(services: [TestWall], accounts: @accounts, data: @data)
    @wall     = Rubbs::Common::Central::Proxy.local(TestWall, @server, aud: 'feedia-bbs')
  end

  def teardown
    @server.stop
    FileUtils.rm_rf(@data)
    Rubbs.config.auth_secrets = []
  end

  def test_the_database_is_the_centrals
    assert File.exist?(File.join(@data, 'test_wall.sqlite3'))
    assert_equal 'ok', @wall.post(actor(@ada.id, 'Ada'), text: 'Hello')['result']
    assert_equal [%w[Ada Hello]], @wall.recent['notes']
  end

  def test_the_roles_are_the_accounts_not_the_boards
    answer = @wall.who(Rubbs::Common::Central::Actor.new(id: @ada.id, name: 'Ada', roles: ['sysop']))
    assert_equal [%w[member], 'feedia-bbs'], [answer['roles'], answer['asker']]
    assert_equal 'forbidden', @wall.wipe(actor(@ada.id, 'Ada'))['result']
    @accounts.grant('Ada', 'sysop')
    assert_equal 'ok', @wall.wipe(actor(@ada.id, 'Ada'))['result']
  end

  def test_who_may_not_ask
    assert_equal 'unknown_account', @wall.who(actor(999, 'Nobody'))['result']
    @accounts.ban('Ada', by: 'test', reason: 'spam')
    assert_equal 'banned', @wall.who(actor(@ada.id, 'Ada'))['result']
  end

  def test_a_guest_cannot_take_an_accounts_name
    assert_equal 'name_taken', @wall.who(guest('ada'))['result']
    assert_equal 'name_taken', @wall.who(guest('AdA'))['result']
    assert_equal 'invalid_name', @wall.who(guest("\u0000!"))['result']
    joe = @wall.who(guest('Joe'))
    assert_equal ['Joe', true], [joe['name'], joe['guest']]
    assert_equal [nil, true], @wall.who(guest(nil)).values_at('name', 'guest')
  end

  def test_the_answers_that_are_not_the_services
    assert_equal 'unknown_op', @wall.call(:shout, guest('Joe'))['result']
    capture_io { assert_equal 'bad_request', @wall.post(guest('Joe'))['result'] }
    assert_equal 'empty', @wall.post(guest('Joe'), text: ' ')['result']
    assert_equal({ 'result' => 'unknown_service' }, @server.dispatch('/nowhere', { 'op' => 'x' }))
  end

  private

  def actor(id, name) = Rubbs::Common::Central::Actor.new(id: id, name: name, caller_key: 'line:1')

  def guest(name) = Rubbs::Common::Central::Actor.guest(name, caller_key: 'line:2')
end

class CentralOverHttpTest < Minitest::Test
  def setup
    Rubbs::Test.auth_secret
    @data     = Dir.mktmpdir('central')
    @accounts = Rubbs::Test.accounts(roles: ['member'])
    @ada      = @accounts.register('Ada', 'secret1')
    @server   = Rubbs::Common::Central::Server.new(
      services: [Rubbs::Common::Auth::Service, TestWall], accounts: @accounts, port: 0, host: '127.0.0.1', data: @data
    )
    @thread   = @server.start
    @client   = Rubbs::Common::Central::Client.new("http://127.0.0.1:#{@server.port}", aud: 'blog-bbs')
  end

  def teardown
    @server.stop
    @thread.kill
    FileUtils.rm_rf(@data)
    Rubbs.config.auth_secrets = []
  end

  def test_a_remote_answers_as_the_local_one
    remote = Rubbs::Common::Central::Proxy.remote(TestWall, @client)
    local  = Rubbs::Common::Central::Proxy.local(TestWall, @server, aud: 'blog-bbs')
    ada    = Rubbs::Common::Central::Actor.new(id: @ada.id, name: 'Ada')
    capture_io { assert_equal 'ok', remote.post(ada, text: 'Hi')['result'] }
    capture_io { assert_equal remote.recent, local.recent }
    capture_io { assert_equal remote.who(ada), local.who(ada) }
  end

  def test_the_accounts_are_a_service_too
    remote = Rubbs::Common::Auth::Remote.new(client: @client)
    capture_io { assert_equal 'Ada', remote.log_in('ada', 'secret1', caller_key: 'line:1').name }
    capture_io { assert_equal :wrong, remote.log_in('ada', 'nope', caller_key: 'line:1') }
    capture_io { assert_equal :known, remote.account_state('ADA') }
  end

  def test_one_way_to_fail
    wall = Rubbs::Common::Central::Proxy.remote(TestWall, @client)
    url    = "http://127.0.0.1:#{@server.port}/wall"
    forged = Rubbs::Common::Web::HTTP.post(
      url,
      body:        '{"op":"recent"}',
      headers:     { 'X-RuBBS-Central' => 'x' },
      public_only: false
    )
    assert_equal [403, '{"error":"signature"}'], [forged.status, forged.body]
    Rubbs.config.auth_secrets = []
    capture_io { assert_equal Rubbs::Common::Central::UNAVAILABLE, wall.recent }
    Rubbs::Test.auth_secret
    away = Rubbs::Common::Central::Client.new('http://127.0.0.1:9', timeout: 1)
    capture_io { assert_equal Rubbs::Common::Central::UNAVAILABLE, Rubbs::Common::Central::Proxy.remote(TestWall, away).recent }
  end

  def test_health
    response = Rubbs::Common::Web::HTTP.get("http://127.0.0.1:#{@server.port}/health", public_only: false)
    assert_equal [200, 'ok'], [response.status, response.body]
  end
end

class CentralBoardTest < Minitest::Test
  NAMES = %i[title log_tag env_prefix].freeze

  def setup
    Rubbs::Test.auth_secret
    @names = NAMES.to_h { |name| [name, Rubbs.config.public_send(name)] }
  end

  def teardown
    @names.each { |name, value| Rubbs.config.public_send("#{name}=", value) }
    Rubbs.config.central&.server&.stop
    Rubbs.config.central = nil
    Rubbs.config.auth = nil
    Rubbs.config.auth_secrets = []
  end

  def test_the_central_serves_its_board_and_the_accounts
    data     = Dir.mktmpdir('central')
    accounts = Rubbs::Test.accounts
    Rubbs::Common::Board::BoardDefinition.new('Gate BBS') do
      auth(accounts, login: :menu)
      central serve: 0, services: [TestWall], data: data
      modern { text 'hi' }
    end.configure
    link = Rubbs.config.central
    assert link.central?
    assert_equal %w[/auth /wall], link.server.services.keys
    assert_equal 'ok', Rubbs.central(TestWall).post(Rubbs::Common::Central::Actor.guest('Joe'), text: 'Hi')['result']
  ensure
    FileUtils.rm_rf(data)
  end

  def test_another_board_asks_the_central
    Rubbs::Common::Board::BoardDefinition.new('Blog BBS') do
      central 'http://gate-bbs:8090'
      auth login: :menu
      modern { text 'hi' }
    end.configure
    assert_equal 'http://gate-bbs:8090', Rubbs.config.central.client.url
    assert_kind_of Rubbs::Common::Auth::Remote, Rubbs.config.auth.directory
    assert_equal 'blog-bbs', Rubbs.config.auth.directory.client.audience
  end

  def test_without_a_central_a_service_is_away
    assert_equal Rubbs::Common::Central::UNAVAILABLE, Rubbs.central(TestWall).recent
    assert_raises(ArgumentError) { Rubbs::Common::Board::BoardDefinition.new('X BBS') { auth login: :menu }.configure }
  end
end

# A wall of a network that adds to TestWall.
class TestBigWall < TestWall
  op(:count, actor: false) { |_, **| { count: database[:notes].count } }
end

class CentralServiceInheritanceTest < Minitest::Test
  def test_a_subclass_keeps_the_parents_path_database_and_ops
    assert_equal ['/wall', :test_wall], [TestBigWall.path, TestBigWall.database.first]
    assert_equal %w[post recent who wipe count], TestBigWall.ops.keys
    refute TestWall.ops.key?('count')
    data = Dir.mktmpdir('central')
    server = Rubbs::Common::Central::Server.new(services: [TestBigWall], data: data)
    proxy = Rubbs::Common::Central::Proxy.local(TestWall, server, aud: 'x-bbs')
    assert_equal 0, proxy.call(:count)['count']
  ensure
    server&.stop
    FileUtils.rm_rf(data) if data
  end
end
