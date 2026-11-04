# frozen_string_literal: true

require 'test_helper'
require 'ui/modern'
require 'ui/petscii'

class FacesTest < Minitest::Test
  include TmpGuestbook

  Board = Struct.new(:guestbook) do
    def services = { guestbook: guestbook }
  end

  def test_the_c64_face_signs_and_reads
    keys = ['s', *'ada'.chars, :enter, *'hello'.chars, :enter, :enter, 'r', :enter, :enter, 'q', 'q']
    session = BBS::Test::Session.new(keys: keys, petscii: true)
    UI::Petscii.new(session, {}, Board.new(@guestbook)).run
    assert_equal ['ada'], @guestbook.all.map(&:name)
    assert_includes session.output, 'Thank you for signing'
  end

  def test_the_modern_face_opens_the_guestbook
    BBS.config.board = Board.new(@guestbook)
    app = UI::Modern::APP.build(session: BBS::Test::Session.new, session_id: 's', context: {})
    assert_equal 'Guestbook', app.window(:entries).title
    assert_equal '0 entries', app.statusbar.right_text.split(' │ ').first
  ensure
    BBS.config.board = nil
  end
end
