# frozen_string_literal: true

require 'rake'
require 'rake/testtask'
require_relative '../rubbs'
require_relative 'common/board/check'

module Rubbs
  # The rake tasks of a board, loaded with <tt>require 'rubbs/rake'</tt> in its
  # Rakefile (not by <tt>require 'rubbs'</tt>):
  #
  #   require 'rubbs/rake'
  #   Rubbs::Rake.board
  #
  # [<tt>rake test</tt>]      the board's tests, <tt>test/**/*_test.rb</tt>
  #                           with +test+ and +lib+ on the load path
  # [<tt>rake bbs:check</tt>] the board's shape (Rubbs::Common::Board::Check); fails with
  #                           the list of what is out of it
  # [<tt>rake</tt>]           both, what CI runs
  module Rake
    extend ::Rake::DSL

    # Defines the tasks for the board in the current folder. +options+ go
    # to Rubbs::Common::Board::Check.run: +skip+ (rule names) and the options rules read
    # (<tt>faces: false</tt>).
    def self.board(**options)
      ::Rake::TestTask.new(:test) do |t|
        t.libs << 'test' << 'lib'
        t.test_files = FileList['test/**/*_test.rb']
        t.warning = false
      end

      namespace :bbs do
        desc "Checks the board's files, names and declarations (Rubbs::Common::Board::Check)"
        task(:check) { Rake.check(Dir.pwd, **options) }
      end

      task default: [:test, 'bbs:check']
    end

    # Runs Rubbs::Common::Board::Check on the board at +root+ and prints what is out of
    # shape. Raises (and so fails the task) when anything is.
    def self.check(root, **)
      findings = Common::Board::Check.run(root, **)
      if findings.empty?
        puts "bbs:check: #{Common::Board::Check.rules.size} rules, the board is in shape"
        return
      end

      findings.each { |finding| warn "  #{finding}" }
      abort "bbs:check: #{findings.size} out of shape"
    end
  end
end
