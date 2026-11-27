# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

class GotoTest < Minitest::Test
  def test_a_gateway_to_a_place_forwards_it
    gateway = Rubbs::Common::Line::Gateway.new(host: 'localhost', port: 2331, name: 'Commodex BBS', forward: true)
    session = Rubbs::Test::Session.new
    assert_nil gateway.goto
    refute gateway.send(:forwarded, session).key?('BBS_GOTO')
    there = gateway.to('game:Q55815')
    assert_equal 'game:Q55815', there.send(:forwarded, session)['BBS_GOTO']
    assert_nil gateway.goto, 'the gateway itself stays as it was'
  end

  def test_the_place_is_taken_once
    session = Rubbs::Test::Session.new(forwarded: { 'BBS_GOTO' => ' machine:Q99775 ' })
    assert_equal 'machine:Q99775', session.take_goto
    assert_nil session.take_goto
    assert_nil Rubbs::Test::Session.new.take_goto
  end

  def test_the_place_is_a_forwarded_variable
    assert_includes Rubbs::Common::Line::Telnet::Environ::FORWARDED, 'BBS_GOTO'
  end
end
