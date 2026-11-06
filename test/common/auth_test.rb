# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

class AuthTokenTest < Minitest::Test
  ADA = Rubbs::Common::Auth::Identity.new(id: 7, name: 'Ada', roles: %w[member blogger], source: :login)

  def setup = Rubbs::Test.auth_secret

  def teardown = Rubbs.config.auth_secrets = []

  def test_a_token_carries_the_identity_once
    token = Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs')
    found = Rubbs::Common::Auth::Token.verify(token, aud: 'blog-bbs')
    assert_equal [7, 'Ada', %w[blogger member], :token], [found.id, found.name, found.roles, found.source]
    assert_raises(Rubbs::Common::Auth::Token::Replayed) { Rubbs::Common::Auth::Token.verify(token, aud: 'blog-bbs') }
  end

  def test_a_token_is_for_one_board_and_one_minute
    token = Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs')
    assert_raises(Rubbs::Common::Auth::Token::WrongAudience) { Rubbs::Common::Auth::Token.verify(token, aud: 'wiki-bbs') }
    old = Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs', now: Time.now - 120)
    assert_raises(Rubbs::Common::Auth::Token::Expired) { Rubbs::Common::Auth::Token.verify(old, aud: 'blog-bbs') }
  end

  def test_a_changed_token_or_another_secret_is_refused
    version, kid, payload, signature = Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs').split('.')
    claims = JSON.parse(Rubbs::Common::Auth::Token.decode(payload)).merge('roles' => ['sysop'])
    forged = [version, kid, Rubbs::Common::Auth::Token.encode(JSON.generate(claims)), signature].join('.')
    assert_raises(Rubbs::Common::Auth::Token::BadSignature) { Rubbs::Common::Auth::Token.verify(forged, aud: 'blog-bbs') }

    other = Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs')
    Rubbs::Test.auth_secret('another secret')
    assert_raises(Rubbs::Common::Auth::Token::BadSignature) { Rubbs::Common::Auth::Token.verify(other, aud: 'blog-bbs') }
    assert_raises(Rubbs::Common::Auth::Token::Malformed) { Rubbs::Common::Auth::Token.verify('nonsense', aud: 'blog-bbs') }
  end

  def test_the_old_secret_is_taken_while_the_secret_changes
    token = Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs')
    Rubbs.config.auth_secrets = ['the new secret', Rubbs::Test::SECRET]
    assert_equal 'Ada', Rubbs::Common::Auth::Token.verify(token, aud: 'blog-bbs').name
  end

  def test_no_secret_no_token
    Rubbs.config.auth_secrets = []
    assert_raises(Rubbs::Common::Auth::Token::NoSecret) { Rubbs::Common::Auth::Token.issue(ADA, aud: 'blog-bbs') }
  end
end

class AuthPasswordTest < Minitest::Test
  def test_a_digest_matches_its_password_only
    digest = Rubbs::Common::Auth::Password.digest('secret1', iterations: 1000)
    assert Rubbs::Common::Auth::Password.match?(digest, 'secret1')
    refute Rubbs::Common::Auth::Password.match?(digest, 'secret2')
    refute Rubbs::Common::Auth::Password.match?(nil, '')
    assert Rubbs::Common::Auth::Password.rehash?(digest)
  end

  def test_a_hex_digest_of_an_older_board_carries_over
    salt = 'ab' * 16
    hex  = OpenSSL::KDF.pbkdf2_hmac('secret1', salt: [salt].pack('H*'), iterations: 1000, length: 32, hash: 'sha256')
      .unpack1('H*')
    assert Rubbs::Common::Auth::Password.match?(Rubbs::Common::Auth::Password.from_hex(salt, hex, iterations: 1000), 'secret1')
  end
end

class AuthDirectoryTest < Minitest::Test
  def setup
    @directory = Rubbs::Test.accounts(roles: ['member'], reserved: ['Root'], guard: Rubbs::Common::Auth::Guard.new(per_name: 2))
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
    assert_match(/login_failed/, err)
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

  def test_a_banned_account_cannot_log_in
    capture_io do
      @directory.register('Ada', 'secret1')
      @directory.grant('ada', :sysop, by: 'test')
      assert_equal :ok, @directory.ban('ada', by: 'Tasi', reason: 'spam')
      assert_equal :wrong, @directory.log_in('ada', 'nope', caller_key: 'line:1')
      assert_equal :banned, @directory.log_in('ada', 'secret1', caller_key: 'line:1')
      assert_equal :banned, @directory.change_password('ada', 'secret1', 'secret9', caller_key: 'line:1')
    end
    entry = @directory.entry('ADA')
    assert_equal [true, 'Tasi', 'spam', %w[member sysop]], [entry.banned?, entry.banned_by, entry.ban_reason, entry.roles]
    capture_io { assert_equal :ok, @directory.unban('ada', by: 'Tasi') }
    assert_equal 'Ada', @directory.log_in('ada', 'secret1', caller_key: 'line:1').name
    assert_equal :unknown, @directory.ban('nobody', by: 'Tasi')
  end

  def test_the_accounts_of_a_sysop_list
    capture_io do
      %w[Bob Ada Cecil].each { |name| @directory.register(name, 'secret1') }
      @directory.grant('cecil', :blogger)
    end
    assert_equal %w[Ada Bob Cecil], @directory.accounts.map(&:name)
    assert_equal %w[Cecil], @directory.accounts('blogger').map(&:name)
    assert_equal %w[Ada], @directory.accounts('AD').map(&:name)
    assert_equal %w[blogger member], @directory.accounts.last.roles
    refute @directory.accounts.first.banned?
  end

  def test_statistics
    capture_io do
      @directory.register('Ada', 'secret1')
      @directory.grant('ada', :blogger)
      @directory.import('Old', Rubbs::Common::Auth::Password.digest('x', iterations: 1000), created_at: '2020-01-01T00:00:00Z')
      @directory.log_in('ada', 'secret1', caller_key: 'line:1')
    end
    stats = @directory.statistics
    assert_equal [2, { 'blogger' => 1, 'member' => 1 }], [stats[:accounts], stats[:roles]]
    assert_equal [1, 1, 1], stats.values_at(:new_day, :new_week, :seen_day)
  end

  def test_an_import_keeps_the_id_and_joins_roles
    digest = Rubbs::Common::Auth::Password.digest('secret1', iterations: 1000)
    assert_equal 42, @directory.import('Ada', digest, roles: %w[blogger], id: 42).id
    again = @directory.import('ada', Rubbs::Common::Auth::Password.digest('other'), roles: %w[sysop])
    assert_equal [42, %w[blogger sysop]], [again.id, again.roles]
    assert_equal 'Ada', @directory.log_in('ada', 'secret1', caller_key: 'line:1').name
  end
end

class AuthRemoteTest < Minitest::Test
  def setup
    Rubbs::Test.auth_secret
    @directory = Rubbs::Test.accounts(roles: ['member'])
    @directory.register('Ada', 'secret1')
    @api = Rubbs::Common::Auth::API.new(@directory, port: 0, host: '127.0.0.1')
    @thread = @api.start
    @remote = Rubbs::Common::Auth::Remote.new("http://127.0.0.1:#{@api.port}/auth", aud: 'blog-bbs')
  end

  def teardown
    @api.stop
    @thread.kill
    Rubbs.config.auth_secrets = []
  end

  def test_the_other_board_logs_in_through_the_api
    ada = @remote.log_in('ada', 'secret1', caller_key: 'line:1')
    assert_equal ['Ada', %w[member], :login], [ada.name, ada.roles, ada.source]
    capture_io { assert_equal :wrong, @remote.log_in('ada', 'nope', caller_key: 'line:1') }
    assert @remote.known?('ADA')
    assert_equal false, @remote.known?('bob')
    assert_equal 'Bob', @remote.register('Bob', 'secret2').name
  end

  def test_a_request_without_the_secret_is_refused
    assert_equal({ 'error' => 'signature' }, @api.answer('{"op":"known","name":"ada"}', 'forged'))
    Rubbs.config.auth_secrets = []
    capture_io { assert_equal :unavailable, @remote.log_in('ada', 'secret1', caller_key: 'line:1') }
    capture_io { assert_equal :unavailable, @remote.account_state('ada') }
  end
end

class AuthLineTest < Minitest::Test
  def setup
    Rubbs::Test.auth_secret
    @directory = Rubbs::Test.accounts
    @directory.register('Ada', 'secret1')
    @saved = Rubbs.config.auth
  end

  def teardown
    Rubbs.config.auth = @saved
    Rubbs.config.auth_secrets = []
  end

  def test_a_forwarded_key_signs_the_caller_in
    key = Rubbs::Common::Auth::Token.issue(@directory.find('ada'), aud: Rubbs.config.log_tag)
    session = Rubbs::Test::Session.new(forwarded: { 'RUBBS_AUTH_KEY' => key })
    assert_equal(['Ada', :token], Rubbs::Common::Auth.from_line(session).then { |i| [i.name, i.source] })
    capture_io { assert Rubbs::Common::Auth.from_line(session).guest? }
  end

  def test_the_login_at_the_call
    setup = Rubbs::Common::Auth::Setup.new(directory: @directory, login: :call, guests: true)
    answers = %w[ada secret1]
    session = Rubbs::Test::Session.new
    login = Rubbs::Common::Auth::Login.new(setup, session, ask: ->(_, **) { answers.shift }, tell: ->(_) {})
    assert_equal :ok, login.at_call
    assert_equal 'Ada', session.identity.name

    guest = Rubbs::Test::Session.new
    login = Rubbs::Common::Auth::Login.new(setup, guest, ask: ->(_, **) { 'Visitor' }, tell: ->(_) {})
    assert_equal :ok, login.at_call
    assert_equal ['Visitor', true], [guest.identity.name, guest.identity.guest?]
  end

  def test_without_guests_a_stranger_stays_out
    setup = Rubbs::Common::Auth::Setup.new(directory: @directory, login: :call, guests: false)
    login = Rubbs::Common::Auth::Login.new(setup, Rubbs::Test::Session.new, ask: ->(_, **) { 'Visitor' }, tell: ->(_) {})
    assert_equal :halt, login.at_call
  end

  def test_three_wrong_passwords_end_the_login
    setup = Rubbs::Common::Auth::Setup.new(directory: @directory, login: :call, guests: true)
    told  = []
    login = Rubbs::Common::Auth::Login.new(setup, Rubbs::Test::Session.new, ask: ->(_, **) { 'nope' }, tell: ->(t) { told << t })
    capture_io { assert_nil login.run('ada') }
    assert_equal 3, told.size
  end

  def test_a_command_for_a_role
    Rubbs.config.auth = Rubbs::Common::Auth::Setup.new(directory: @directory, login: :menu, guests: true)
    session = Rubbs::Test::Session.new
    ran = []
    app = Rubbs::Modern::Application.define do
      command(:write, 'Write', key: 'F4', role: :blogger) { ran << :write }
      menu 'Blog', :write, :log_in, :log_out
    end.build(session: session, session_id: 's', context: {})
    item = app.menubar.menus.first.items.first
    refute item.enabled?
    app.statusbar.handle_event(Rubbs::Modern::Widgets::Event.key(:f4))
    assert_empty ran
    session.identity = Rubbs::Common::Auth::Identity.new(id: 1, name: 'Ada', roles: %w[blogger])
    assert item.enabled?
    app.statusbar.handle_event(Rubbs::Modern::Widgets::Event.key(:f4))
    assert_equal [:write], ran
  end

  def test_the_gateway_hands_a_signed_in_caller_on
    gateway = Rubbs::Common::Line::Gateway.new(
      host:        '127.0.0.1',
      port:        1,
      name:        'TTG Blog BBS',
      public_only: false,
      forward:     true
    )
    caller = Rubbs::Test::Session.new(identity: @directory.find('ada'), forwarded: { 'BBS_CLIENT_IP' => '8.8.8.8' })
    sent = gateway.send(:forwarded, caller)
    assert_equal 'Ada', Rubbs::Common::Auth::Token.verify(sent['RUBBS_AUTH_KEY'], aud: 'ttg-blog-bbs').name
    refute gateway.send(:forwarded, Rubbs::Test::Session.new).key?('RUBBS_AUTH_KEY')
  end

  def test_a_login_box_runs_its_block_after_a_good_login
    Rubbs.config.auth = Rubbs::Common::Auth::Setup.new(directory: @directory, login: :menu, guests: true)
    session = Rubbs::Test::Session.new
    app = Rubbs::Modern::Application.define { theme :synchronet }.build(session: session, session_id: 's', context: {})
    seen = []
    form = app.log_in { |who| seen << who.name }
    after = ->(who) { seen << who.name }
    assert_equal :close, app.send(:submit_login, Rubbs.config.auth, { name: 'ada', password: 'secret1' }, form, after)
    assert_equal ['Ada'], seen
    assert_equal 'Ada', session.identity.name
  end

  def test_a_command_with_a_condition
    open = false
    app = Rubbs::Modern::Application.define do
      command(:peek, 'Peek', if: -> { open }) { :peeked }
      menu 'Look', :peek
    end.build(session: Rubbs::Test::Session.new, session_id: 's', context: {})
    item = app.menubar.menus.first.items.first
    refute item.enabled?
    open = true
    assert item.enabled?
  end

  def test_a_name_that_cannot_be_checked_comes_in_only_as_a_nameless_guest
    away = Object.new
    def away.account_state(_) = :unavailable
    setup = Rubbs::Common::Auth::Setup.new(directory: away, login: :call, guests: true)
    session = Rubbs::Test::Session.new
    told = []
    login = Rubbs::Common::Auth::Login.new(setup, session, ask: ->(_, **) { 'Ada' }, tell: ->(t) { told << t })
    assert_equal :ok, login.at_call
    assert_nil session.identity.name
    assert_equal [Rubbs::Common::Auth::Login::WORDS[:unavailable]], told
  end
end

class AuthProfileTest < Minitest::Test
  def setup
    @directory = Rubbs::Test.accounts(roles: ['member'])
    @setup = Rubbs::Common::Auth::Setup.new(directory: @directory, login: :menu, guests: true)
    @look  = Rubbs::Common::Auth::Profile::Look.new(note: 'One account for every board.')
  end

  # A key alone is pressed as it is; a word in brackets is typed and RETURN pressed.
  def keys(*presses) = presses.flat_map { |press| press.is_a?(Array) ? [*press.first.chars, :enter] : [press] }

  def profile(*presses, petscii: false, identity: nil)
    session = Rubbs::Test::Session.new(keys: keys(*presses), petscii: petscii, identity: identity)
    capture_io { Rubbs::Common::Auth::Profile.new(session, @setup, @look).run }
    session
  end

  def test_a_guest_makes_an_account
    session = profile('n', ['Ada'], ['secret1'], ['secret1'], ' ', 'b')
    assert_equal ['Ada', %w[member]], [session.identity.name, session.identity.roles]
    text = session.output
    assert_includes text, 'PROFILE'
    assert_includes text, 'One account for every board.'
    assert_includes text, 'Your account is ready'
    assert_includes text, 'Logged in as Ada'
  end

  def test_log_in_and_out_on_a_c64
    @directory.register('Ada', 'secret1')
    session = profile('l', ['ada'], ['secret1'], ' ', 'l', ' ', 'b', petscii: true)
    assert session.identity.guest?
    assert_includes session.output, 'Welcome, Ada.'
    assert_includes session.output, 'You are logged out.'
    assert_includes session.output, "\r\r"
    assert_includes session.raw, Rubbs::Petscii::LOWERCASE.b
  end

  def test_from_the_splash_space_goes_to_the_main_screen
    session = Rubbs::Test::Session.new(keys: keys(['Ada'], ['secret1'], ['secret1'], 'x', ' '))
    capture_io { Rubbs::Common::Auth::Profile.new(session, @setup, @look).run(start: :register) }
    assert_equal 'Ada', session.identity.name
    assert_includes session.output, 'Press space to main screen'
  end

  def test_from_a_menu_no_hint_and_space_takes_nothing
    session = profile(' ', 'b')
    refute_includes session.output, 'Press space to main screen'
  end

  def test_the_menu_follows_who_is_on_the_line
    ada = @directory.register('Ada', 'secret1')
    signed = profile('b', identity: ada).output
    assert_includes signed, 'Change password'
    refute_includes signed, 'New account'
    assert_includes profile('b').output, 'New account'
  end

  def test_the_drawing_is_in_the_middle
    Dir.mktmpdir do |dir|
      art = "size: [4, 1]\ncharset: cp437\npalette:\n  w: white\nchars: |2\n  XXXX\ncolors: |2\n  wwww\n"
      File.write(File.join(dir, 'mini.yml'), art)
      @look = Rubbs::Common::Auth::Profile::Look.new(modern: Rubbs::Common::Art.load(File.join(dir, 'mini.yml')))
      assert_match(/^ {38}\e\[[0-9;]*mXXXX/, profile('b').output)
    end
  end

  def test_a_board_adds_its_own_place
    opened = []
    Rubbs::Common::Auth::Profile.extra(:sysop, 'SysOp', if: ->(s) { s.identity.role?(:sysop) }) { |s| opened << s.identity.name }
    sysop = Rubbs::Common::Auth::Identity.new(id: 1, name: 'Ada', roles: %w[sysop], source: :login)
    shown = profile('s', 'b', identity: sysop).output
    assert_includes shown, 'SysOp'
    assert_equal ['Ada'], opened
    member = Rubbs::Common::Auth::Identity.new(id: 2, name: 'Bob', roles: %w[member], source: :login)
    refute_includes profile('b', identity: member).output, 'SysOp'
  ensure
    Rubbs::Common::Auth::Profile.clear_extras
  end

  def test_a_board_without_a_login_says_so
    session = Rubbs::Test::Session.new(keys: [' '])
    Rubbs::Common::Auth::Profile.new(session, nil, @look).run
    assert_includes session.output, 'Nobody logs in on this board.'
  end
end
