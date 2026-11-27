# frozen_string_literal: true

require_relative '../test_helper'
require 'rubbs/test'
require_relative 'pages_test'

class TestCaseTest < Rubbs::Test::Case
  WORDS = ->(line) { Rubbs::Common::Screens::Pages.new(line).run(PagesTest::Words.new(%w[alpha beta])) }

  test 'the keys go one by one and the screen is looked at between them' do
    call(WORDS) do
      see 'alpha'
      never_see 'Word: beta'
      press :down, :enter
      see 'Word: beta'
    end
  end

  test 'a C64 face draws on a canvas' do
    call(WORDS, face: :petscii) do
      press :down
      see 'BETA'
    end
    assert_predicate line, :petscii?
  end

  test 'a flow with the terminal question gets the face forwarded' do
    flow = Rubbs::Common::Call::Terminal.flow(
      title:   'Test BBS',
      modern:  Rubbs::Common::Call::Flow.define { call { session.write("modern face\r\n") && nil } },
      petscii: Rubbs::Common::Call::Flow.define { call { session.write('C64') && nil } }
    )
    call(flow, face: :modern) { see 'modern face' }
    never_see 'YOUR TERMINAL'
  end

  test 'the caller is who as says' do
    call(->(line) { line.write("Hello, #{line.identity.name}.") }, as: 'Ada') { see 'Hello, Ada.' }
    assert line.identity.signed_in?
  end

  test 'an error of the call is raised in the test' do
    assert_raises(ArgumentError) { call(->(_line) { raise ArgumentError, 'broken' }) }
  end

  test 'the config goes back after the test' do
    outer = Rubbs.config
    inner = Class.new(Rubbs::Test::Case).new('inner')
    inner.setup
    Rubbs.config.title = 'changed in a test'
    inner.teardown
    assert_same outer, Rubbs.config
    refute_equal 'changed in a test', outer.title
  end

  def test_a_test_of_the_same_name_is_refused
    assert_raises(ArgumentError) { self.class.test('the config goes back after the test') { nil } }
  end
end
