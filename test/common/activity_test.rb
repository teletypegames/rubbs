# frozen_string_literal: true

require_relative '../test_helper'
require 'rubbs/test'

class ActivityTest < Minitest::Test
  Activity = Rubbs::Common::Line::Activity

  def test_inside_a_door_the_caller_is_doing_the_door_and_after_it_the_section_again
    line = Rubbs::Test::Session.new
    line.activity = Activity.new(kind: :section, name: 'feeds')
    inside = nil
    door = Rubbs::Common::Call::Door.new(:sermo, ->(session, _context) { inside = session.activity })
    capture_io { door.run(line) }
    assert_equal Activity.new(kind: :door, name: 'sermo'), inside
    assert_equal 'door sermo', inside.to_s
    assert_equal 'feeds', line.activity.to_s
  end

  def test_doing_puts_the_activity_back_after_an_error
    line = Rubbs::Test::Session.new
    assert_raises(RuntimeError) { line.doing(:board, 'Alexandria BBS') { raise 'dropped' } }
    assert_nil line.activity
    assert_equal '› Alexandria BBS', Activity.new(kind: :board, name: 'Alexandria BBS').to_s
  end
end
