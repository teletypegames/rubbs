# frozen_string_literal: true

require 'test_helper'
require 'json'

class LogTest < Minitest::Test
  def setup
    @saved = [BBS.config.log_format, BBS.config.log_tag]
    BBS.config.log_tag = 'test-bbs'
  end

  def teardown
    BBS.config.log_format, BBS.config.log_tag = @saved
  end

  def test_text_line_with_fields
    _, err = capture_io { BBS.log('index', 'loaded', rfcs: 9700) }
    assert_equal "test-bbs: index: loaded rfcs=9700\n", err
  end

  def test_text_error_carries_its_backtrace
    _, err = capture_io { BBS.log('event', failure) }
    lines = err.lines
    assert_equal "test-bbs: event: RuntimeError: broken\n", lines.first
    assert_operator lines.size, :>, 1
    assert(lines.drop(1).all? { |line| line.start_with?('  ') })
  end

  def test_a_warning_has_no_backtrace
    _, err = capture_io { BBS.log('refresh', failure, level: :warn, retry_in: 5) }
    assert_equal "test-bbs: refresh: RuntimeError: broken retry_in=5\n", err
  end

  def test_json_line
    BBS.config.log_format = :json
    _, err = capture_io { BBS::Log.with_session('abc') { BBS.log('call', 'ended', seconds: 3) } }
    record = JSON.parse(err)
    assert_equal({ 'level' => 'info', 'board' => 'test-bbs', 'tag' => 'call', 'msg' => 'ended',
                   'session' => 'abc', 'seconds' => 3 }, record.except('time'))
  end

  def test_json_error
    BBS.config.log_format = :json
    _, err = capture_io { BBS.log('face', failure) }
    record = JSON.parse(err)
    assert_equal %w[error RuntimeError broken], record.values_at('level', 'error', 'msg')
    refute_empty record['backtrace']
    refute record.key?('session')
  end

  def test_unknown_level
    assert_raises(ArgumentError) { BBS.log('x', 'y', level: :loud) }
  end

  private

  def failure
    raise 'broken'
  rescue RuntimeError => e
    e
  end
end
