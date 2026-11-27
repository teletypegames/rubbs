# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

class LoginsTest < Minitest::Test
  def teardown = Rubbs::Common::Auth::Logins.clear

  def ada = Rubbs::Common::Auth::Identity.new(id: 7, name: 'Ada', roles: [], source: :token)

  def test_the_blocks_run_once_an_account_is_signed_in_and_the_call_has_its_face
    seen = []
    Rubbs::Common::Auth::Logins.on_login { |session| seen << session.identity.name }
    session = Rubbs::Test::Session.new(identity: ada)
    refute Rubbs::Common::Auth::Logins.signed_in(session), 'no face yet'
    session.face = :petscii
    assert Rubbs::Common::Auth::Logins.signed_in(session)
    refute Rubbs::Common::Auth::Logins.signed_in(session), 'once a call'
    assert_equal ['Ada'], seen
  end

  def test_a_guest_runs_nothing_and_an_error_is_logged
    Rubbs::Common::Auth::Logins.on_login { |_session| raise 'broken' }
    guest = Rubbs::Test::Session.new.tap { |s| s.face = :modern }
    refute Rubbs::Common::Auth::Logins.signed_in(guest)
    signed = Rubbs::Test::Session.new(identity: ada).tap { |s| s.face = :modern }
    _, err = capture_io { assert Rubbs::Common::Auth::Logins.signed_in(signed) }
    assert_match(/broken/, err)
  end

  def test_a_session_runs_them_when_its_face_is_set
    seen = 0
    Rubbs::Common::Auth::Logins.on_login { |_session| seen += 1 }
    line = Rubbs::Common::Line::Session.allocate
    line.instance_variable_set(:@identity, ada)
    line.face = :modern
    line.identity = ada
    assert_equal 1, seen
  end
end
