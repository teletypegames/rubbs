# frozen_string_literal: true

require 'test_helper'
require 'json'

class LogTest < Minitest::Test
  def setup
    @saved = [Rubbs.config.log_format, Rubbs.config.log_tag]
    Rubbs.config.log_tag = 'test-bbs'
  end

  def teardown
    Rubbs.config.log_format, Rubbs.config.log_tag = @saved
  end

  def test_text_line_with_fields
    _, err = capture_io { Rubbs.log('index', 'loaded', rfcs: 9700) }
    assert_equal "test-bbs: index: loaded rfcs=9700\n", err
  end

  def test_text_error_carries_its_backtrace
    _, err = capture_io { Rubbs.log('event', failure) }
    lines = err.lines
    assert_equal "test-bbs: event: RuntimeError: broken\n", lines.first
    assert_operator lines.size, :>, 1
    assert(lines.drop(1).all? { |line| line.start_with?('  ') })
  end

  def test_a_warning_has_no_backtrace
    _, err = capture_io { Rubbs.log('refresh', failure, level: :warn, retry_in: 5) }
    assert_equal "test-bbs: refresh: RuntimeError: broken retry_in=5\n", err
  end

  def test_json_line
    Rubbs.config.log_format = :json
    _, err = capture_io { Rubbs::Common::Log.with_session('abc') { Rubbs.log('call', 'ended', seconds: 3) } }
    record = JSON.parse(err)
    assert_equal(
      {
        'level'   => 'info',
        'board'   => 'test-bbs',
        'tag'     => 'call',
        'msg'     => 'ended',
        'session' => 'abc',
        'seconds' => 3
      },
      record.except('time')
    )
  end

  def test_json_error
    Rubbs.config.log_format = :json
    _, err = capture_io { Rubbs.log('face', failure) }
    record = JSON.parse(err)
    assert_equal %w[error RuntimeError broken], record.values_at('level', 'error', 'msg')
    refute_empty record['backtrace']
    refute record.key?('session')
  end

  def test_recent_lines_are_kept_in_order
    capture_io do
      Rubbs.log('index', 'loaded', rfcs: 9700)
      Rubbs.log('fetch', RuntimeError.new('boom'))
    end
    first, last = Rubbs::Common::Log.recent(2)
    assert_equal ['index', :info, 'loaded', { rfcs: 9700 }], [first.tag, first.level, first.message, first.fields]
    assert_equal [:error, 'RuntimeError: boom'], [last.level, last.message]
    capture_io { (Rubbs::Common::Log::RECENT + 5).times { |i| Rubbs.log('n', i.to_s) } }
    assert_equal [Rubbs::Common::Log::RECENT, (Rubbs::Common::Log::RECENT + 4).to_s], [Rubbs::Common::Log.recent.size, Rubbs::Common::Log.recent.last.message]
  end

  def test_unknown_level
    assert_raises(ArgumentError) { Rubbs.log('x', 'y', level: :loud) }
  end

  private

  def failure
    raise 'broken'
  rescue RuntimeError => e
    e
  end
end
