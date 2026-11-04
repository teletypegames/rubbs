# frozen_string_literal: true

require 'test_helper'

class BackgroundTest < Minitest::Test
  def test_log_names_the_board_and_the_tag
    BBS.config.log_tag = 'test-bbs'
    _, err = capture_io { BBS.log('refresh', RuntimeError.new('down')) }
    assert_equal "test-bbs: refresh: RuntimeError: down\n", err
  ensure
    BBS.config.log_tag = 'bbs'
  end

  def test_runs_until_it_succeeds_once
    tries = 0
    _, err = capture_io do
      BBS.background('index', retry_after: 0.01) { (tries += 1) < 3 ? raise('not yet') : :done }.join(2)
    end
    assert_equal 3, tries
    assert_equal 2, err.lines.size
    assert_match(/index: RuntimeError: not yet retry_in=0.02/, err.lines.last)
  end

  def test_runs_every_so_often
    runs = Queue.new
    thread = BBS.background('tick', every: 0.01) { runs << 1 }
    3.times { runs.pop }
    assert_equal 'bbs: tick', thread.name
  ensure
    thread&.kill
  end

  def test_the_pause_doubles_up_to_the_cap
    pauses = []
    work   = BBS::Background.new('x', retry_after: 1, max_retry: 3) { raise 'down' if pauses.size < 4 }
    work.define_singleton_method(:sleep) { |seconds| pauses << seconds }
    capture_io { work.run }
    assert_equal [1, 2, 3, 3], pauses
  end
end
