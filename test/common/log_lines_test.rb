# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'rubbs/test'

# The log lines a log pipeline counts (Grafana's BBS dashboards): the
# caller's address on every line of a call, the facts of +call ended+, and
# the +use+, +door+, +transfer+, +discord+, +rate limit+ and +server+ lines.
class LogLinesTest < Minitest::Test
  E = Rubbs::Common::Line::Telnet::Environ

  def setup
    @saved = [Rubbs.config.log_format, Rubbs.config.log_tag]
    Rubbs.config.log_format = :json
    Rubbs.config.log_tag    = 'test-bbs'
  end

  def teardown
    Rubbs.config.log_format, Rubbs.config.log_tag = @saved
  end

  # The JSON records written by the block.
  def records(&)
    _, err = capture_io(&)
    err.lines.map { |line| JSON.parse(line) }
  end

  def session_from(ip)
    session = FakeSession.new
    session.define_singleton_method(:peer_ip) { ip }
    session
  end

  def forward(session, vars)
    session.fake_line.caller.write(E.info(vars) + [255, 250, 31, 0, 100, 0, 30, 255, 240].pack('C*'))
    session.settle(timeout: 0.3)
  end

  def test_a_line_in_a_call_carries_the_callers_address
    session = session_from('198.51.100.9')
    lines = records { Rubbs::Common::Log.with_session('abc', caller: session) { Rubbs.log('index', 'loaded') } }
    assert_equal %w[abc 198.51.100.9], lines.first.values_at('session', 'ip')
  ensure
    session.fake_line.close
  end

  def test_the_forwarded_address_once_it_came
    session = session_from('172.18.0.2')
    forward(session, 'BBS_CLIENT_IP' => '203.0.113.7', 'BBS_VIA' => 'bbs-web')
    lines = records { Rubbs::Common::Log.with_session('abc', caller: session) { Rubbs.log('x', 'y') } }
    assert_equal '203.0.113.7', lines.first['ip']
    assert_equal 'bbs-web', session.call_via
  ensure
    session.fake_line.close
  end

  def test_text_lines_carry_the_address_too
    Rubbs.config.log_format = :text
    session = session_from('198.51.100.9')
    _, err = capture_io { Rubbs::Common::Log.with_session('abc', caller: session) { Rubbs.log('index', 'loaded', n: 1) } }
    assert_equal "test-bbs: index: loaded ip=198.51.100.9 n=1\n", err
  ensure
    session.fake_line.close
  end

  def test_no_address_outside_a_call
    refute records { Rubbs.log('index', 'loaded') }.first.key?('ip')
  end

  def test_where_a_call_came_from
    assert_equal 'telnet', with_peer('8.8.8.8', &:call_via)
    assert_equal 'local', with_peer('172.18.0.9', &:call_via)
    assert_equal 'local', with_peer(nil, &:call_via)
  end

  def with_peer(ip)
    session = session_from(ip)
    yield session
  ensure
    session.fake_line.close
  end

  def test_the_address_outlives_the_line
    server = TCPServer.new('127.0.0.1', 0)
    client = TCPSocket.new('127.0.0.1', server.addr[1])
    session = Rubbs::Common::Line::Session.new(server.accept)
    session.line.close
    assert_equal '127.0.0.1', session.peer_ip
    assert_equal 'local', session.call_via
  ensure
    client&.close
    server&.close
  end

  def test_call_ended_facts
    session = session_from('8.8.8.8')
    session.face = :petscii
    session.identity = Rubbs::Common::Auth::Identity.new(id: 1, name: 'mr.zero', roles: [])
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    facts = Rubbs::Common::Line::Server.new(port: 0).send(:call_facts, session, started, :hung_up)
    assert_equal(
      {
        ip:      '8.8.8.8',
        seconds: 0,
        end:     :hung_up,
        via:     'telnet',
        face:    'petscii',
        cols:    80,
        rows:    24,
        naws:    false,
        user:    'mr.zero'
      },
      facts.except(:session)
    )
  ensure
    session.fake_line.close
  end

  def test_a_guest_and_no_face
    session = session_from('172.18.0.9')
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    facts = Rubbs::Common::Line::Server.new(port: 0).send(:call_facts, session, started, :hung_up)
    assert_equal %w[none local], facts.values_at(:face, :via)
    refute facts.key?(:user)
  ensure
    session.fake_line.close
  end

  def test_the_face_of_a_terminal_pick_is_kept
    session = FakeSession.new
    session.define_singleton_method(:settle) { |**| true }
    session.fake_line.caller.write("2\r")
    Timeout.timeout(5) { Rubbs::Common::Call::Terminal.pick(session, 'T', nil) }
    assert_equal :petscii, session.face
  ensure
    session.fake_line.close
  end

  def test_a_board_with_one_face_sets_it
    session = Rubbs::Test::Session.new
    Timeout.timeout(5) { Rubbs::Common::Call::FlowRunner.new(session, 'id', Rubbs::Common::Call::Terminal.only(:modern, Rubbs::Common::Call::Flow.define { nil })).run }
    assert_equal :modern, session.face
  end

  def test_use_names
    assert_equal 'bbc news en', Rubbs::Common::Log.use_name("\e[90mBBC  News\e[37m — en!")
    assert_equal 'feed list', Rubbs::Common::Log.use_name('&Feed list…')
    assert_equal 40, Rubbs::Common::Log.use_name('x' * 99).size
    assert_nil records { Rubbs::Common::Log.use('', kind: :menu, face: :petscii) }.first
  end

  def test_a_command_writes_a_use_line
    app = Rubbs::Modern::Application.define do
      command(:feeds, 'Feeds', key: 'F2') { nil }
    end.build(session: Rubbs::Test::Session.new, session_id: 's')
    lines = records { app.statusbar.hints.find { |h| h.key == 'F2' }.on_activate.call }
    use = lines.find { |l| l['tag'] == 'use' }
    assert_equal %w[feeds modern command], use.values_at('msg', 'face', 'kind')
  end

  class Menu < Rubbs::Petscii::Face
    main_menu do
      item('f', 'feeds') { nil }
      log_off
    end
  end

  def test_a_menu_item_writes_a_use_line
    session = Rubbs::Test::Session.new(keys: %w[f q])
    lines = records { Menu.new(session, {}).run }
    uses = lines.select { |l| l['tag'] == 'use' }
    assert_equal([%w[feeds petscii menu]], uses.map { |l| l.values_at('msg', 'face', 'kind') })
  end

  def test_a_door_writes_a_crossed_line
    session = Rubbs::Test::Session.new
    door = Rubbs::Common::Call::Door.new(:games, ->(_s, _c) {})
    line = records { door.run(session) }.find { |l| l['tag'] == 'door' }
    assert_equal %w[crossed games ok], line.values_at('msg', 'door', 'result')
    assert_equal 0, line['seconds']
  end

  def test_a_failed_door
    session = Rubbs::Test::Session.new
    door = Rubbs::Common::Call::Door.new(:games, ->(_s, _c) { raise 'broken' })
    line = records { door.run(session) }.find { |l| l['tag'] == 'door' }
    assert_equal 'failed', line['result']
  end

  def test_a_gateway_writes_one_crossed_line
    session = FakeSession.new
    server = TCPServer.new('127.0.0.1', 0)
    Thread.new { server.accept.close }
    gateway = Rubbs::Common::Line::Gateway.new(host: '127.0.0.1', port: server.addr[1], public_only: false, name: 'Far')
    door = Rubbs::Common::Call::Door.new(:far, gateway)
    Thread.new { sleep 0.3; session.fake_line.caller.write('x') }
    lines = records { door.run(session) }.select { |l| l['tag'] == 'door' }
    assert_equal 1, lines.size
    assert_equal ['Far', "127.0.0.1:#{server.addr[1]}", 'board', 'ok'], lines.first.values_at('door', 'host', 'by', 'result')
  ensure
    server&.close
    session.fake_line.close
  end

  def test_a_gateway_that_does_not_connect
    session = FakeSession.new
    session.fake_line.caller.write('x')
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    gateway = Rubbs::Common::Line::Gateway.new(host: '127.0.0.1', port: port, public_only: false)
    line = records { gateway.call(session) }.find { |l| l['tag'] == 'door' }
    assert_equal 'failed', line['result']
    refute line.key?('by')
  ensure
    session.fake_line.close
  end

  def test_a_transfer_line
    Rubbs::Common::Files::Xmodem.stub(:send_file, :cancelled) do
      line = records { Rubbs::Common::Files::Transfer.send(Rubbs::Test::Session.new, :xmodem, 'GAME.PRG', 'abc') }.first
      assert_equal %w[transfer cancelled GAME.PRG xmodem warn], line.values_at('tag', 'msg', 'file', 'protocol', 'level')
      assert_equal 3, line['bytes']
    end
    Rubbs::Common::Files::Zmodem.stub(:send_files, :ok) do
      sent = records { Rubbs::Common::Files::Transfer.send(Rubbs::Test::Session.new, :zmodem, 'A', 'abc') }
      assert_equal 'sent', sent.first['msg']
    end
  end

  def test_a_dropped_transfer_line
    Rubbs::Common::Files::Zmodem.stub(:send_files, :hangup) do
      nil
      _, err = capture_io { assert_raises(Rubbs::Common::Line::Hangup) { Rubbs::Common::Files::Transfer.send(Rubbs::Test::Session.new, :zmodem, 'A', 'x') } }
      line = JSON.parse(err.lines.first)
      assert_equal 'dropped', line['msg']
    end
  end

  def test_discord_lines
    hook = Rubbs::Common::Web::DiscordWebhook.new('https://discord.invalid/x', relay_max: 1, label: 'feedia: suggestions')
    hook.stub(:deliver, nil) do
      records { hook.post('one') }
      line = records { hook.post('two') }.find { |l| l['tag'] == 'discord' }
      assert_equal ['limited', 'feedia: suggestions', 'warn'], line.values_at('msg', 'label', 'level')
    end
  end

  def test_discord_sent_and_failed
    http = TinyHTTP.new { |path, client| client.write(path == '/ok' ? http_response(204, '') : http_response(500, 'no')) }
    sent = Rubbs::Common::Web::DiscordWebhook.new(http.url('/ok'), label: 'L')
    failed = Rubbs::Common::Web::DiscordWebhook.new(http.url('/bad'), label: 'L')
    all = records do
      sent.send(:deliver, '{}')
      failed.send(:deliver, '{}')
    end
    lines = all.select { |l| l['tag'] == 'discord' }
    assert_equal([%w[sent L], %w[failed L]], lines.map { |l| l.values_at('msg', 'label') })
    assert_equal '500', lines.last['http']
  ensure
    http&.close
  end

  def test_a_refusal_names_the_full_limits
    tips  = Rubbs::Common::Line::RateLimit.new(limit: 1, per: 60, name: 'tips')
    board = Rubbs::Common::Line::RateLimit.new(limit: 5, per: 60)
    records { Rubbs::Common::Line::RateLimit.allow_all?([[tips, 'k'], [board, :all]]) }
    line = records { refute Rubbs::Common::Line::RateLimit.allow_all?([[tips, 'k'], [board, :all]]) }.first
    assert_equal ['rate limit', 'refused', 'tips', 'info'], line.values_at('tag', 'msg', 'limit', 'level')
    assert_equal 'unnamed', records { Rubbs::Common::Line::RateLimit.new(limit: 0, per: 1).allow?(:x) }.first['limit']
  end

  def test_the_version
    assert_match(/\A\d+\.\d+\.\d+/, Rubbs.version)
  end
end
