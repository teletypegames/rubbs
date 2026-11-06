# frozen_string_literal: true

require 'yaml'
require_relative 'multi_runner/board_ref'
require_relative 'multi_runner/fingerprint'
require_relative 'multi_runner/output'
require_relative 'multi_runner/launch'
require_relative 'multi_runner/child'
require_relative 'multi_runner/status'
require_relative 'multi_runner/restarts'
require_relative 'multi_runner/supervision'

module Rubbs
  # Many boards in one container: a supervisor that starts each board in a
  # process of its own (a fork), and watches them.
  #
  #   require 'rubbs'
  #
  #   runner = Rubbs::MultiRunner.new(root: 'boards', settings: 'boards.yml')
  #   runner.boards = Rubbs::MultiRunner.discover('boards')   # the default
  #   runner.run!
  #
  # A board is a folder with a +bbs.rb+ that declares it with Rubbs.board.
  # The supervisor never loads a board's code itself: the board's process
  # changes into the folder, takes its port and caller limit from the
  # settings, loads +bbs.rb+ and runs the declared board
  # (Rubbs::Common::Board::BoardDefinition#run!). So two boards may name their
  # classes alike, and a board restarted reads its code from the disk anew.
  #
  # What the supervisor does (see Supervision):
  #
  # - every line a board writes goes out on the supervisor's stderr; a line
  #   that is not a JSON log record is wrapped in one with the board's name
  #   (Output)
  # - a board that ends is started again, after 1, 2, 4 … 60 seconds
  # - a board that fails its health probe (Rubbs::Common::Line::Health) three
  #   times, or grows over its +memory+, is restarted in order
  # - when <tt><root>/.revision</tt> changes, only the boards whose files
  #   changed (Fingerprint) are restarted, one at a time; nothing is
  #   (re)started while <tt><root>/.deploying</tt> exists
  # - the state of every board goes to <tt><state>/multi_runner.json</tt>
  #   (Status)
  # - SIGTERM stops every board in order (Rubbs::Common::Line::Server#stop),
  #   the stragglers are killed after BBS_SHUTDOWN_SECONDS and 5 more
  #
  # BBS_BOARDS (names, comma separated) starts only those boards.
  class MultiRunner
    include Supervision

    # The file name of the state, in the state folder.
    STATUS_FILE = 'multi_runner.json'

    @loading  = false
    @declared = nil

    class << self
      # The boards in +root+: a BoardRef for every folder with a +bbs.rb+,
      # by name.
      def discover(root)
        Dir.glob(File.join(root, '*', 'bbs.rb')).map { |file| BoardRef.at(File.dirname(file)) }
      end

      # Whether a board's +bbs.rb+ is being loaded by #capture now.
      def loading? = @loading

      # Runs the block (the load of a +bbs.rb+) and returns the
      # Rubbs::Common::Board::BoardDefinition that Rubbs.board declared in it,
      # or +nil+.
      def capture
        @loading  = true
        @declared = nil
        yield
        @declared
      ensure
        @loading = false
      end

      # Keeps +definition+ for #capture (Rubbs.board calls it). Returns it.
      def declare(definition) = (@declared = definition)
    end

    # The boards to run: BoardRef objects (discover) or
    # Rubbs::Common::Board::BoardDefinition objects already made.
    attr_writer :boards

    # The folder of the boards (watched for <tt>.revision</tt>) and of the
    # state file.
    attr_reader :root, :state

    # [root]     the folder of the boards
    # [settings] a YAML file or a Hash: per board name its +port+,
    #            +max_sessions+, +memory+ (<tt>160m</tt>), +enabled+ and
    #            +env+ (more environment variables)
    # [state]    the folder of the state file
    # [name]     the supervisor's own name in the log
    # [only]     the names to start (default: BBS_BOARDS, else all)
    def initialize(
      root: 'boards',
      settings: {},
      state: ENV.fetch('BBS_STATE_DIR', 'state'),
      name: 'multi-runner',
      only: ENV.fetch('BBS_BOARDS', '')
    )
      @root     = File.expand_path(root)
      @settings = settings.is_a?(Hash) ? settings : (YAML.safe_load_file(settings) || {})
      @state    = File.expand_path(state)
      @name     = name
      @only     = only.to_s.split(',').map(&:strip).reject(&:empty?)
      @boards   = nil
    end

    # The boards this runner starts: those given (or discovered in #root),
    # less those disabled in the settings or left out by +only+.
    def boards
      (@boards || self.class.discover(@root)).map { |board| BoardRef.of(board) }.select do |ref|
        @settings.fetch(ref.name, {}).fetch('enabled', true) && (@only.empty? || @only.include?(ref.name))
      end
    end

    # Starts every board and supervises them until SIGTERM (or SIGINT).
    # Returns +nil+ when the last board has stopped.
    def run!
      Rubbs.config.log_tag = @name
      @children = boards.map { |ref| Child.new(ref, @settings.fetch(ref.name, {}), output: output) }
      raise ArgumentError, "no boards in #{@root}" if @children.empty?

      supervise
      nil
    end

    private

    def output = @output ||= Output.new
  end
end
