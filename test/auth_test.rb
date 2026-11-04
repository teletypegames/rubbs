# frozen_string_literal: true

require 'test_helper'
require 'bbs/test'

class AuthTokenTest < Minitest::Test
  ADA = BBS::Auth::Identity.new(id: 7, name: 'Ada', roles: %w[member blogger], source: :login)

  def setup = BBS::Test.auth_secret

  def teardown = BBS.config.auth_secrets = []

  def test_a_token_carries_the_identity_once
    token = BBS::Auth::Token.issue(ADA, aud: 'blog-bbs')
    found = BBS::Auth::Token.verify(token, aud: 'blog-bbs')
    assert_equal [7, 'Ada', %w[blogger member], :token], [found.id, found.name, found.roles, found.source]
    assert_raises(BBS::Auth::Token::Replayed) { BBS::Auth::Token.verify(token, aud: 'blog-bbs') }
  end

  def test_a_token_is_for_one_board_and_one_minute
    token = BBS::Auth::Token.issue(ADA, aud: 'blog-bbs')
    assert_raises(BBS::Auth::Token::WrongAudience) { BBS::Auth::Token.verify(token, aud: 'wiki-bbs') }
    old = BBS::Auth::Token.issue(ADA, aud: 'blog-bbs', now: Time.now - 120)
    assert_raises(BBS::Auth::Token::Expired) { BBS::Auth::Token.verify(old, aud: 'blog-bbs') }
  end

  def test_a_changed_token_or_another_secret_is_refused
    version, kid, payload, signature = BBS::Auth::Token.issue(ADA, aud: 'blog-bbs').split('.')
    claims = JSON.parse(BBS::Auth::Token.decode(payload)).merge('roles' => ['sysop'])
    forged = [version, kid, BBS::Auth::Token.encode(JSON.generate(claims)), signature].join('.')
    assert_raises(BBS::Auth::Token::BadSignature) { BBS::Auth::Token.verify(forged, aud: 'blog-bbs') }

    other = BBS::Auth::Token.issue(ADA, aud: 'blog-bbs')
    BBS::Test.auth_secret('another secret')
    assert_raises(BBS::Auth::Token::BadSignature) { BBS::Auth::Token.verify(other, aud: 'blog-bbs') }
    assert_raises(BBS::Auth::Token::Malformed) { BBS::Auth::Token.verify('nonsense', aud: 'blog-bbs') }
  end

  def test_the_old_secret_is_taken_while_the_secret_changes
    token = BBS::Auth::Token.issue(ADA, aud: 'blog-bbs')
    BBS.config.auth_secrets = ['the new secret', BBS::Test::SECRET]
    assert_equal 'Ada', BBS::Auth::Token.verify(token, aud: 'blog-bbs').name
  end

  def test_no_secret_no_token
    BBS.config.auth_secrets = []
    assert_raises(BBS::Auth::Token::NoSecret) { BBS::Auth::Token.issue(ADA, aud: 'blog-bbs') }
  end
end

class AuthPasswordTest < Minitest::Test
  def test_a_digest_matches_its_password_only
    digest = BBS::Auth::Password.digest('secret1', iterations: 1000)
    assert BBS::Auth::Password.match?(digest, 'secret1')
    refute BBS::Auth::Password.match?(digest, 'secret2')
    refute BBS::Auth::Password.match?(nil, '')
    assert BBS::Auth::Password.rehash?(digest)
  end

  def test_a_hex_digest_of_an_older_board_carries_over
    salt = 'ab' * 16
    hex  = OpenSSL::KDF.pbkdf2_hmac('secret1', salt: [salt].pack('H*'), iterations: 1000, length: 32, hash: 'sha256')
      .unpack1('H*')
    assert BBS::Auth::Password.match?(BBS::Auth::Password.from_hex(salt, hex, iterations: 1000), 'secret1')
  end
end

class AuthDirectoryTest < Minitest::Test
  def setup
    @directory = BBS::Test.accounts(roles: ['member'], reserved: ['Root'], guard: BBS::Auth::Guard.new(per_name: 2))
  end

  def test_register_and_log_in
    ada = @directory.register('Ada', 'secret1')
    assert_equal [%w[member], :login], [ada.roles, ada.source]
    assert_equal 'Ada', @directory.log_in('ADA', 'secret1', caller_key: 'line:1').name
    assert @directory.known?('ada')
  end

  def test_what_cannot_be_registered
    @directory.register('Ada', 'secret1')
    assert_equal :taken, @directory.register('ada', 'secret1')
    assert_equal :look_alike, @directory.register('Аda', 'secret1')
    assert_equal :reserved, @directory.register('R00t', 'secret1')
    assert_equal :too_short, @directory.register('Bob', 'abc')
    assert_equal :mismatch, @directory.register('Bob', 'secret1', 'secret2')
    assert_equal :invalid, @directory.register('', 'secret1')
  end

  def test_wrong_passwords_lock_the_name
    _, err = capture_io do
      @directory.register('Ada', 'secret1')
      2.times { assert_equal :wrong, @directory.log_in('ada', 'nope', caller_key: 'line:1') }
    end
    assert_match(/wrong name or password/, err)
    assert_equal :locked, @directory.log_in('ada', 'secret1', caller_key: 'line:2')
  end

  def test_roles_and_passwords
    @directory.register('Ada', 'secret1')
    @directory.grant('ada', :blogger, by: 'test')
    assert_equal %w[blogger member], @directory.find('ada').roles
    @directory.revoke('ada', :member)
    assert_equal %w[blogger], @directory.find('ada').roles
    assert_equal :ok, @directory.change_password('ada', 'secret1', 'secret9', caller_key: 'line:1')
    assert_equal 'Ada', @directory.log_in('ada', 'secret9', caller_key: 'line:1').name
    assert_equal :unknown, @directory.grant('nobody', :sysop)
  end

  def test_an_import_keeps_the_id_and_joins_roles
    digest = BBS::Auth::Password.digest('secret1', iterations: 1000)
    assert_equal 42, @directory.import('Ada', digest, roles: %w[blogger], id: 42).id
    again = @directory.import('ada', BBS::Auth::Password.digest('other'), roles: %w[sysop])
    assert_equal [42, %w[blogger sysop]], [again.id, again.roles]
    assert_equal 'Ada', @directory.log_in('ada', 'secret1', caller_key: 'line:1').name
  end
end

class AuthRemoteTest < Minitest::Test
  def setup
    BBS::Test.auth_secret
    @directory = BBS::Test.accounts(roles: ['member'])
    @directory.register('Ada', 'secret1')
    @api = BBS::Auth::API.new(@directory, port: 0, host: '127.0.0.1')
    @thread = Thread.new { @api.instance_variable_get(:@server).start }
    @remote = BBS::Auth::Remote.new("http://127.0.0.1:#{@api.port}/auth", aud: 'blog-bbs')
  end

  def teardown
    @api.stop
    @thread.join(2)
    BBS.config.auth_secrets = []
  end

  def test_the_other_board_logs_in_through_the_api
    ada = @remote.log_in('ada', 'secret1', caller_key: 'line:1')
    assert_equal ['Ada', %w[member], :login], [ada.name, ada.roles, ada.source]
    capture_io { assert_equal :wrong, @remote.log_in('ada', 'nope', caller_key: 'line:1') }
    assert @remote.known?('ADA')
    refute @remote.known?('bob')
    assert_equal 'Bob', @remote.register('Bob', 'secret2').name
  end

  def test_a_request_without_the_secret_is_refused
    assert_equal({ error: 'signature' }, @api.answer('{"op":"known","name":"ada"}', 'forged'))
    BBS.config.auth_secrets = []
    capture_io { assert_equal :unavailable, @remote.log_in('ada', 'secret1', caller_key: 'line:1') }
  end
end

class AuthLineTest < Minitest::Test
  def setup
    BBS::Test.auth_secret
    @directory = BBS::Test.accounts
    @directory.register('Ada', 'secret1')
    @saved = BBS.config.auth
  end

  def teardown
    BBS.config.auth = @saved
    BBS.config.auth_secrets = []
  end

  def test_a_forwarded_key_signs_the_caller_in
    key = BBS::Auth::Token.issue(@directory.find('ada'), aud: BBS.config.log_tag)
    session = BBS::Test::Session.new(forwarded: { 'RUBBS_AUTH_KEY' => key })
    assert_equal(['Ada', :token], BBS::Auth.from_line(session).then { |i| [i.name, i.source] })
    capture_io { assert BBS::Auth.from_line(session).guest? }
  end

  def test_the_login_at_the_call
    setup = BBS::Auth::Setup.new(directory: @directory, login: :call, guests: true)
    answers = %w[ada secret1]
    session = BBS::Test::Session.new
    login = BBS::Auth::Login.new(setup, session, ask: ->(_, **) { answers.shift }, tell: ->(_) {})
    assert_equal :ok, login.at_call
    assert_equal 'Ada', session.identity.name

    guest = BBS::Test::Session.new
    login = BBS::Auth::Login.new(setup, guest, ask: ->(_, **) { 'Visitor' }, tell: ->(_) {})
    assert_equal :ok, login.at_call
    assert_equal ['Visitor', true], [guest.identity.name, guest.identity.guest?]
  end

  def test_without_guests_a_stranger_stays_out
    setup = BBS::Auth::Setup.new(directory: @directory, login: :call, guests: false)
    login = BBS::Auth::Login.new(setup, BBS::Test::Session.new, ask: ->(_, **) { 'Visitor' }, tell: ->(_) {})
    assert_equal :halt, login.at_call
  end

  def test_three_wrong_passwords_end_the_login
    setup = BBS::Auth::Setup.new(directory: @directory, login: :call, guests: true)
    told  = []
    login = BBS::Auth::Login.new(setup, BBS::Test::Session.new, ask: ->(_, **) { 'nope' }, tell: ->(t) { told << t })
    capture_io { assert_nil login.run('ada') }
    assert_equal 3, told.size
  end

  def test_a_command_for_a_role
    BBS.config.auth = BBS::Auth::Setup.new(directory: @directory, login: :menu, guests: true)
    session = BBS::Test::Session.new
    ran = []
    app = BBS::Application.define do
      command(:write, 'Write', key: 'F4', role: :blogger) { ran << :write }
      menu 'Blog', :write, :log_in, :log_out
    end.build(session: session, session_id: 's', context: {})
    item = app.menubar.menus.first.items.first
    refute item.enabled?
    app.statusbar.handle_event(BBS::Event.key(:f4))
    assert_empty ran
    session.identity = BBS::Auth::Identity.new(id: 1, name: 'Ada', roles: %w[blogger])
    assert item.enabled?
    app.statusbar.handle_event(BBS::Event.key(:f4))
    assert_equal [:write], ran
  end

  def test_the_gateway_hands_a_signed_in_caller_on
    gateway = BBS::Gateway.new(host: '127.0.0.1', port: 1, name: 'TTG Blog BBS', public_only: false, forward: true)
    caller = BBS::Test::Session.new(identity: @directory.find('ada'), forwarded: { 'BBS_CLIENT_IP' => '8.8.8.8' })
    sent = gateway.send(:forwarded, caller)
    assert_equal 'Ada', BBS::Auth::Token.verify(sent['RUBBS_AUTH_KEY'], aud: 'ttg-blog-bbs').name
    refute gateway.send(:forwarded, BBS::Test::Session.new).key?('RUBBS_AUTH_KEY')
  end

  def test_a_login_box_runs_its_block_after_a_good_login
    BBS.config.auth = BBS::Auth::Setup.new(directory: @directory, login: :menu, guests: true)
    session = BBS::Test::Session.new
    app = BBS::Application.define { theme :synchronet }.build(session: session, session_id: 's', context: {})
    seen = []
    form = app.log_in { |who| seen << who.name }
    assert_equal :close, app.send(:submit_login, BBS.config.auth, { name: 'ada', password: 'secret1' }, form, ->(who) { seen << who.name })
    assert_equal ['Ada'], seen
    assert_equal 'Ada', session.identity.name
  end
end
