# frozen_string_literal: true

require 'test_helper'
require 'rubbs/rake'
require 'fileutils'

class RakeTasksTest < Minitest::Test
  def test_a_board_gets_test_check_and_the_default
    app = Rake::Application.new
    Rake.application = app
    Rubbs::Rake.board(faces: false)
    assert app.lookup('test')
    assert app.lookup('bbs:check')
    assert_equal %w[test bbs:check], app.lookup('default').prerequisites
  ensure
    Rake.application = Rake::Application.new
  end

  def test_a_repository_of_boards_gets_the_tasks_over_its_folders
    app = Rake::Application.new
    Rake.application = app
    Rubbs::Rake.multi(root: 'boards')
    assert app.lookup('test')
    assert app.lookup('bbs:check')
    Dir.mktmpdir do |root|
      %w[alpha beta common].each do |name|
        FileUtils.mkdir_p(File.join(root, name))
        File.write(File.join(root, name, 'Rakefile'), '')
      end
      assert_equal(%w[alpha beta common], Rubbs::Rake.folders(root, '').map { |dir| File.basename(dir) })
      assert_equal(%w[beta], Rubbs::Rake.folders(root, 'beta, gamma').map { |dir| File.basename(dir) })
    end
  ensure
    Rake.application = Rake::Application.new
  end
end
