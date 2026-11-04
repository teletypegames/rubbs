# frozen_string_literal: true

require 'test_helper'
require 'bbs/rake'

class RakeTasksTest < Minitest::Test
  def test_a_board_gets_test_check_and_the_default
    app = Rake::Application.new
    Rake.application = app
    BBS::Rake.board(faces: false)
    assert app.lookup('test')
    assert app.lookup('bbs:check')
    assert_equal %w[test bbs:check], app.lookup('default').prerequisites
  ensure
    Rake.application = Rake::Application.new
  end
end
