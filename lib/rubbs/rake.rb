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

    # Defines the tasks of a repository of many boards (Rubbs::MultiRunner),
    # in its root Rakefile: each folder of +root+ with a Rakefile runs its
    # own <tt>rake test</tt>, and each board (a folder with a +bbs.rb+) its
    # <tt>rake bbs:check</tt>, in a process of its own (two boards may name
    # their classes alike). +only+ (default: BOARDS, names comma separated)
    # chooses the folders. Every folder runs; the task fails at the end,
    # naming the folders that failed.
    #
    #   require 'rubbs/rake'
    #   Rubbs::Rake.multi
    def self.multi(root: 'boards', only: ENV.fetch('BOARDS', ''))
      folders = -> { Rake.folders(root, only) }
      desc 'Runs the tests of every folder of the boards'
      task(:test) { Rake.each_folder(folders.call, 'test') }
      namespace :bbs do
        desc 'Checks every board (Rubbs::Common::Board::Check)'
        task(:check) { Rake.each_folder(folders.call.select { |dir| File.file?(File.join(dir, 'bbs.rb')) }, 'bbs:check') }
      end
      task default: [:test, 'bbs:check']
    end

    # The folders of +root+ with a Rakefile, by name; only those named in
    # +only+ (a comma separated String) when it names any.
    def self.folders(root, only)
      names = only.to_s.split(',').map(&:strip).reject(&:empty?)
      Dir.glob(File.join(root, '*', 'Rakefile')).map { |file| File.dirname(file) }.sort.select do |dir|
        names.empty? || names.include?(File.basename(dir))
      end
    end

    # Runs <tt>rake task</tt> in each of +dirs+ (with Bundler, in a process
    # of its own). Raises (and so fails the task) naming the folders where it
    # failed.
    def self.each_folder(dirs, task)
      failed = dirs.reject do |dir|
        puts "==> #{File.basename(dir)}: rake #{task}"
        system('bundle', 'exec', 'rake', task, chdir: dir)
      end
      abort "rake #{task} failed in: #{failed.map { |dir| File.basename(dir) }.join(', ')}" if failed.any?
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
