# frozen_string_literal: true

require 'test_helper'

class FlowTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def run_flow(input, &)
    @session.fake_line.caller.write(input)
    Timeout.timeout(5) { BBS::FlowRunner.new(@session, 'id1', BBS::Flow.define(&)).run }
  end

  def test_ask_stores_the_transformed_answer
    seen = nil
    run_flow("ada\r\n") do
      ask :name, prompt: 'Name', transform: :upcase
      call { |ctx, _| seen = ctx[:name] }
    end
    assert_equal 'ADA', seen
  end

  def test_a_refused_answer_halts
    result = run_flow("nope\r\n") { ask :mail, prompt: 'Mail', validate: :email }
    assert_equal :halt, result
    assert_includes @session.received, 'Farewell'
  end

  def test_gate_halts_on_a_failed_check
    assert_equal :halt, run_flow('') { gate(denied: 'No.') { false } }
    assert_includes @session.received, 'No.'
  end

  def test_confirm_runs_its_steps_on_yes
    said = []
    run_flow("y\r\n") { confirm('Sure?') { call { said << :yes } } }
    assert_equal [:yes], said
  end

  def test_confirm_without_steps_halts_on_no
    assert_equal :halt, run_flow("n\r\n") { confirm('Sure?', denied: 'Bye.') }
  end

  def test_menu_runs_the_option_taken_and_exit_menu_leaves_it
    taken = []
    result = run_flow("1\r2\r") do
      menu '>', loop: true do
        option('one') { call { taken << 1 } }
        option('leave') { exit_menu }
      end
      call { taken << :after }
    end
    assert_nil result
    assert_equal [1, :after], taken
  end

  def test_a_failing_call_is_reported_and_the_flow_goes_on
    after = false
    _, err = capture_io { run_flow('') { call { raise 'boom' }; call { after = true } } }
    assert after
    assert_match(/boom/, err)
    assert_includes @session.received, 'Something went wrong.'
  end
end
