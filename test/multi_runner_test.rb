# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'rbconfig'

class MultiRunnerTest < Minitest::Test
  BOARD = <<~RUBY
    require 'rubbs'

    FLOW = Rubbs::Common::Call::Flow.define { text 'hello' }

    board = Rubbs.board '%<title>s' do
      modern FLOW
      goodbye false
    end

    board.run! if Rubbs.main?(__FILE__)
  RUBY

  # A board whose call waits for a key, and says which process it is.
  HOLDING = <<~RUBY
    require 'rubbs'

    FLOW = Rubbs::Common::Call::Flow.define do
      call { session.write("hello from \#{Process.pid}\r\n") && nil }
      call { session.readkey && session.write("bye from \#{Process.pid}\r\n") && nil }
    end

    board = Rubbs.board '%<title>s' do
      modern FLOW
      goodbye false
    end

    board.run! if Rubbs.main?(__FILE__)
  RUBY

  Kid = Struct.new(:name, :slug)

  def setup
    @config = Rubbs.config.dup
  end

  def teardown
    Rubbs.instance_variable_set(:@config, @config)
  end

  def test_rubbs_board_declares_and_capture_takes_it
    definition = Rubbs::MultiRunner.capture do
      refute Rubbs.main?($PROGRAM_NAME)
      Rubbs.board('Alpha BBS') { goodbye false }
    end
    assert_equal 'alpha-bbs', definition.slug
    refute Rubbs::MultiRunner.loading?
    assert Rubbs.main?($PROGRAM_NAME)
    refute Rubbs.main?("#{__FILE__}.other")
  end

  def test_discover_and_the_settings_choose_the_boards
    Dir.mktmpdir do |root|
      %w[alpha beta gamma].each { |name| write_board(root, name, 'X BBS') }
      FileUtils.mkdir_p(File.join(root, 'common'))
      assert_equal %w[alpha beta gamma], Rubbs::MultiRunner.discover(root).map(&:name)

      runner = Rubbs::MultiRunner.new(root: root, settings: { 'beta' => { 'enabled' => false } }, only: 'alpha,beta')
      assert_equal %w[alpha], runner.boards.map(&:name)
    end
  end

  def test_memory_and_port_settings
    child = Rubbs::MultiRunner::Child.new(ref('a'), { 'memory' => '160m', 'port' => 2327, 'max_sessions' => 50 }, output: nil)
    assert_equal 160 * 1024 * 1024, child.memory_limit
    assert_equal 2327, child.port
    assert_equal 50, child.max_sessions
    assert_nil Rubbs::MultiRunner::Child.new(ref('a'), {}, output: nil).memory_limit
    assert_raises(ArgumentError) { Rubbs::MultiRunner::Child.new(ref('a'), { 'memory' => 'lots' }, output: nil).memory_limit }
  end

  def test_cpu_and_memory_of_a_process
    skip 'Linux /proc only' unless File.exist?("/proc/#{Process.pid}/stat")
    assert_kind_of Float, Rubbs::MultiRunner::Child.cpu(Process.pid)
    assert_operator Rubbs::MultiRunner::Child.rss(Process.pid), :>, 0
  end

  def test_the_fingerprint_is_of_the_code_only
    Dir.mktmpdir do |dir|
      write_board(dir, 'a', 'A BBS')
      board = File.join(dir, 'a')
      before = Rubbs::MultiRunner::Fingerprint.of(board)
      FileUtils.mkdir_p(File.join(board, 'data'))
      File.write(File.join(board, 'data', 'x.sqlite3'), 'rows')
      File.write(File.join(board, 'README.md'), 'words')
      FileUtils.mkdir_p(File.join(board, 'content', 'hunts'))
      File.write(File.join(board, 'content', 'hunts', 'w1-x.yml'), 'title: X')
      FileUtils.mkdir_p(File.join(board, 'scenarios'))
      File.write(File.join(board, 'scenarios', 'tour.yaml'), 'title: Tour')
      FileUtils.touch(File.join(board, 'bbs.rb'), mtime: Time.now - 3600)
      assert_equal before, Rubbs::MultiRunner::Fingerprint.of(board)
      File.write(File.join(board, 'bbs.rb'), "# changed\n", mode: 'a')
      refute_equal before, Rubbs::MultiRunner::Fingerprint.of(board)
    end
  end

  def test_output_passes_records_and_wraps_the_rest
    io  = StringIO.new
    out = Rubbs::MultiRunner::Output.new(io)
    kid = Kid.new('feedia', nil)
    Rubbs.config.log_format = :json
    out.write("{\"board\":\"feedia-bbs\",\"msg\":\"hi\"}\n", kid)
    out.write("warning: something\n", kid)
    first, second = io.string.lines.map { |line| JSON.parse(line) }
    assert_equal 'hi', first['msg']
    assert_equal 'feedia-bbs', kid.slug
    assert_equal ['feedia-bbs', 'output', 'warn', 'warning: something'], second.values_at('board', 'tag', 'level', 'msg')
    Rubbs.config.log_format = :text
    out.write("plain\n", kid)
    assert_equal 'feedia-bbs: plain', io.string.lines.last.chomp
  end

  def test_the_boards_run_in_processes_and_a_deploy_restarts_only_the_changed
    Dir.mktmpdir do |root|
      ports = { 'alpha' => free_port, 'beta' => free_port }
      with_runner(root, ports) do |boards|
        first = wait_for(root) { |s| s if all_up?(s) }
        ports.each_value { |port| assert_equal(true, wait_until { Rubbs::Common::Line::Health.ask(port: port).first }) }

        File.write(File.join(boards, 'alpha', 'bbs.rb'), "# new\n", mode: 'a')
        File.write(File.join(boards, 'beta', 'NOTES.md'), 'not code')
        File.write(File.join(boards, '.revision'), "abc123\n")

        after = wait_for(root) { |s| s if all_up?(s, revision: 'abc123') }
        refute_equal pids(first)['alpha'], pids(after)['alpha']
        assert_equal pids(first)['beta'], pids(after)['beta']
        assert_equal({ 'deploy' => 1 }, after['boards'].find { |b| b['name'] == 'alpha' }['restarts'])
      end
      ports.each_value { |port| refute Rubbs::Common::Line::Health.ask(port: port, timeout: 1).first }
    end
  end

  def test_a_deploy_hands_over_and_the_old_process_keeps_its_call
    Dir.mktmpdir do |root|
      port = free_port
      with_runner(root, { 'alpha' => port }, template: HOLDING) do |boards|
        first = wait_for(root) { |s| s if all_up?(s) }
        old = pids(first)['alpha']
        call = TCPSocket.new('127.0.0.1', port)
        assert_includes read_until(call, 'hello from'), "hello from #{old}"

        File.write(File.join(boards, 'alpha', 'bbs.rb'), "# new\n", mode: 'a')
        File.write(File.join(boards, '.revision'), "abc123\n")
        after = wait_for(root) { |s| s if all_up?(s, revision: 'abc123') && board(s, 'alpha')['draining'].any? }
        new = pids(after)['alpha']
        refute_equal old, new
        assert_equal([old], board(after, 'alpha')['draining'].map { |d| d['pid'] })
        assert_equal({ 'deploy' => 1 }, board(after, 'alpha')['restarts'])

        second = TCPSocket.new('127.0.0.1', port)
        assert_includes read_until(second, 'hello from'), "hello from #{new}"
        second.close

        call.write('x')
        assert_includes read_until(call, 'bye from'), "bye from #{old}"
        call.close
        wait_for(root) { |s| s if board(s, 'alpha')['draining'].empty? }
      end
    end
  end

  def test_a_board_that_does_not_drain_is_restarted_and_holds_its_lock
    Dir.mktmpdir do |root|
      port = free_port
      with_runner(root, { 'alpha' => port }, settings: { 'alpha' => { 'drain' => false } }) do |boards|
        first = wait_for(root) { |s| s if all_up?(s) }
        assert File.exist?(File.join(boards, 'alpha', 'data', Rubbs::MultiRunner::Launch::LOCK_FILE))
        File.write(File.join(boards, 'alpha', 'bbs.rb'), "# new\n", mode: 'a')
        File.write(File.join(boards, '.revision'), "abc123\n")
        after = wait_for(root) { |s| s if all_up?(s, revision: 'abc123') && pids(s)['alpha'] != pids(first)['alpha'] }
        assert_equal false, board(after, 'alpha')['drains']
        assert_empty board(after, 'alpha')['draining']
        assert_equal({ 'deploy' => 1 }, board(after, 'alpha')['restarts'])
      end
    end
  end

  def test_the_supervisor_drains_and_ends_after_the_last_call
    Dir.mktmpdir do |root|
      port = free_port
      runner = nil
      with_runner(root, { 'alpha' => port }, template: HOLDING) do |_boards, pid|
        runner = pid
        wait_for(root) { |s| s if all_up?(s) }
        call = TCPSocket.new('127.0.0.1', port)
        read_until(call, 'hello from')
        Process.kill('USR2', runner)
        wait_for(root) { |s| s if s['draining'] && board(s, 'alpha')['draining'].any? }
        refute Rubbs::Common::Line::Health.ask(port: port, timeout: 1).first
        assert_nil Process.wait(runner, Process::WNOHANG)

        call.write('x')
        assert_includes read_until(call, 'bye from'), 'bye from'
        call.close
        Timeout.timeout(20) { Process.wait(runner) }
        assert_predicate $CHILD_STATUS, :success?
      end
    end
  end

  private

  def board(state, name) = state['boards'].find { |b| b['name'] == name }

  def read_until(socket, text, seconds = 10)
    got = +''
    deadline = Time.now + seconds
    until got.match?(/#{Regexp.escape(text)}[^\n]*\n/)
      raise "no #{text.inspect} in #{got.inspect}" if Time.now > deadline

      ready = socket.wait_readable(0.5) or next
      got << ready.read_nonblock(4096, exception: false).to_s
    end
    got
  end

  def ref(name) = Rubbs::MultiRunner::BoardRef.new(name: name, dir: "/tmp/#{name}", definition: nil)

  def write_board(root, name, title, template = BOARD)
    FileUtils.mkdir_p(File.join(root, name))
    File.write(File.join(root, name, 'bbs.rb'), format(template, title: title))
  end

  def free_port
    server = TCPServer.new('127.0.0.1', 0)
    server.addr[1]
  ensure
    server&.close
  end

  def all_up?(state, revision: nil)
    state['boards'].all? do |b|
      b['up'] && !b['handing_over'] && b['slug'].end_with?('-bbs') && (revision.nil? || b['revision'] == revision)
    end
  end

  def pids(state) = state['boards'].to_h { |b| [b['name'], b['pid']] }

  def with_runner(root, ports, template: BOARD, settings: {})
    boards = File.join(root, 'boards')
    ports.each_key { |name| write_board(boards, name, "#{name.capitalize} BBS", template) }
    yaml = ports.to_h { |name, port| [name, { 'port' => port }.merge(settings.fetch(name, {}))] }
    File.write(File.join(root, 'boards.yml'), yaml.to_yaml)
    runner = spawn_runner(root)
    yield boards, runner
  ensure
    if runner
      begin
        Process.kill('TERM', runner)
        Timeout.timeout(30) { Process.wait(runner) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end

  def spawn_runner(root)
    lib    = File.expand_path('../lib', __dir__)
    script = <<~RUBY
      require 'rubbs'
      sup = Rubbs::MultiRunner::Supervision
      { WATCH_EVERY: 1, STATUS_EVERY: 1, PROBE_EVERY: 1 }.each do |name, value|
        sup.send(:remove_const, name)
        sup.const_set(name, value)
      end
      Rubbs::MultiRunner.new(root: 'boards', settings: 'boards.yml', state: 'state').run!
    RUBY
    env = { 'BBS_SHUTDOWN_SECONDS' => '1', 'BBS_BOARDS' => nil, 'RUBYLIB' => lib }
    spawn(env, RbConfig.ruby, '-e', script, chdir: root, out: File::NULL, err: File.join(root, 'runner.log'))
  end

  def wait_for(root, seconds = 40)
    found = nil
    wait_until(seconds) do
      found = (state = Rubbs::MultiRunner::Status.read(File.join(root, 'state'))) && yield(state)
    end
    found or flunk("no such state in #{seconds}s; log:\n#{File.read(File.join(root, 'runner.log')) rescue ''}")
  end

  def wait_until(seconds = 20)
    deadline = Time.now + seconds
    until Time.now > deadline
      value = yield
      return value if value

      sleep 0.2
    end
    nil
  end
end
