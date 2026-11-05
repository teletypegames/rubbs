# frozen_string_literal: true

require 'test_helper'
require 'ui/modern'
require 'ui/petscii'

class FacesTest < Minitest::Test
  include TmpGuestbook

  Board = Struct.new(:guestbook, :directory) do
    def services = { guestbook: guestbook, directory: directory }
  end

  def test_the_c64_face_signs_and_reads
    keys = ['s', *'ada'.chars, :enter, *'hello'.chars, :enter, :enter, 'r', :enter, :enter, 'q', 'q']
    session = Rubbs::Test::Session.new(keys: keys, petscii: true)
    UI::Petscii.new(session, {}, Board.new(@guestbook)).run
    assert_equal ['ada'], @guestbook.all.map(&:name)
    assert_includes session.output, 'Thank you for signing'
  end

  def test_a_c64_caller_makes_an_account_and_signs_with_its_name
    directory = Rubbs::Test.accounts
    keys = ['n', *'ada'.chars, :enter, *'secret1'.chars, :enter, *'secret1'.chars, :enter, :enter,
            's', *'hello'.chars, :enter, :enter, 'q', 'q']
    session = Rubbs::Test::Session.new(keys: keys, petscii: true)
    UI::Petscii.new(session, {}, Board.new(@guestbook, directory)).run
    assert_equal 'ada', session.identity.name
    assert_equal ['ada'], @guestbook.all.map(&:name)
  end

  def test_the_modern_face_opens_the_guestbook
    Rubbs.config.board = Board.new(@guestbook)
    app = UI::Modern::APP.build(session: Rubbs::Test::Session.new, session_id: 's', context: {})
    assert_equal 'Guestbook', app.window(:entries).title
    assert_equal 'guest · 0 entries', app.statusbar.right_text.split(' │ ').first
  ensure
    Rubbs.config.board = nil
  end
end
