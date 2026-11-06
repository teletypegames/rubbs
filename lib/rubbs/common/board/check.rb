# frozen_string_literal: true

require_relative '../../../rubbs'

module Rubbs
  module Common
    module Board
      # Checks that a board keeps the shape every rubbs board has: its files and
      # folders, the names of its classes, its +bbs.rb+ a Rubbs.board declaration,
      # and none of the forms rubbs 2 replaced. A family of boards adds its own
      # house rules with Check.rule (ttg-common does). Run by <tt>rake
      # bbs:check</tt> (Rubbs::Rake).
      #
      #   findings = Rubbs::Common::Board::Check.run(Dir.pwd)
      #   findings.each { |f| puts f }
      #
      # A board that differs on purpose says so with +skip+ (rule names) or the
      # options a rule reads (<tt>faces: false</tt> for a board that is a gem).
      module Check
        # One thing out of shape: the +rule+'s name, the +path+ it is about
        # (relative to the board) and what is wrong.
        Finding = Struct.new(:rule, :path, :message) do
          # <tt>path: message (rule)</tt>.
          def to_s = "#{path}: #{message} (#{rule})"
        end

        # A rule: its +name+, a line about what it wants, and the block that
        # looks at a Board and reports with Board#fail.
        Rule = Struct.new(:name, :about, :block)

        # Declares the rule +name+ (a Symbol) with a line +about+ it; the block
        # gets the Board. A later rule of the same name replaces it.
        #
        #   Rubbs::Common::Board::Check.rule(:readme, 'every board has a README') do |board|
        #     board.fail('README.md', 'missing') unless board.file?('README.md')
        #   end
        def self.rule(name, about, &block)
          rules[name] = Rule.new(name, about, block)
        end

        # The declared rules by name.
        def self.rules = @rules ||= {}

        # Runs every rule (but +skip+) on the board at +root+ with +options+.
        # Returns the Finding list, empty when the board is in shape.
        def self.run(root, skip: [], **options)
          board = Board.new(root, options)
          rules.each_value do |rule|
            next if skip.include?(rule.name) || board.skip?(rule.name)

            board.as(rule.name) { rule.block.call(board) }
          end
          board.findings
        end

        # The board a rule looks at: its files, what its +bbs.rb+ declares, and
        # the findings so far.
        class Board
          # The board's folder, the options of the check, and the findings.
          attr_reader :root, :options, :findings

          # The board at +root+ checked with +options+.
          def initialize(root, options = {})
            @root     = File.expand_path(root)
            @options  = options
            @findings = []
            @current  = nil
          end

          # Whether the rule +name+ is turned off for this board.
          def skip?(name) = Array(@options[:skip]).include?(name)

          # Reports what is wrong with +path+; the rule's name is added by the
          # rule that runs.
          def fail(path, message) = @findings << Finding.new(@current, path, message)

          # Runs the block as the rule +name+ (the findings carry its name).
          def as(name)
            @current = name
            yield
          ensure
            @current = nil
          end

          # Whether +path+ is a file of the board.
          def file?(path) = File.file?(File.join(@root, path))

          # The start of a Rubbs.board declaration line.
          DECLARATION_START = /\A(?:board\s*=\s*)?Rubbs\.board /

          # The last line of a +bbs.rb+, after the declaration of +board+:
          # it starts the board when the file is the program.
          RUN_LINE = 'board.run! if Rubbs.main?(__FILE__)'

          # The code lines of the file +path+: no blank lines, no comments.
          def code_lines(path) = read(path).to_s.lines.map(&:rstrip).reject { |l| l.strip.empty? || l.strip.start_with?('#') }

          # The code lines of +bbs.rb+ after the Rubbs.board declaration and
          # its block, or +nil+ without one.
          def after_declaration
            lines = code_lines('bbs.rb')
            start = lines.index { |l| l.match?(DECLARATION_START) } or return nil
            return lines[(start + 1)..] unless lines[start].match?(/\bdo\s*(\|.*\|)?\z/)

            finish = ((start + 1)...lines.size).find { |i| lines[i] == 'end' }
            finish ? lines[(finish + 1)..] : []
          end

          # Whether +path+ is a file of the board or of a folder above it (the
          # Gemfile of a repository of many boards).
          def file_above?(path)
            dir = @root
            loop do
              return true if File.file?(File.join(dir, path))

              parent = File.dirname(dir)
              return false if parent == dir

              dir = parent
            end
          end

          # Whether +path+ is a folder of the board.
          def dir?(path) = File.directory?(File.join(@root, path))

          # The text of +path+, or +nil+ when there is no such file.
          def read(path) = (File.read(File.join(@root, path)) if file?(path))

          # The board's files matching +pattern+, relative to the board.
          def glob(pattern) = Dir.glob(pattern, base: @root).sort

          # The board's Ruby code: +bbs.rb+ and everything under +lib+.
          def ruby_files = [*('bbs.rb' if file?('bbs.rb')), *glob('lib/**/*.rb')]

          # The Rubbs.board line of a +bbs.rb+: the title, the domain, the slug.
          DECLARATION = /^(?:board\s*=\s*)?Rubbs\.board\s+(['"])(.+?)\1(?:\s*,\s*([A-Z]\w*))?(?:\s*,\s*slug:\s*(['"])(.+?)\4)?/

          # The title, the domain class name and the slug of the Rubbs.board
          # declaration in +bbs.rb+ (each +nil+ when it says none).
          def declaration
            @declaration ||= begin
              text = read('bbs.rb').to_s
              match = text.match(DECLARATION)
              match ? { title: match[2], domain: match[3], slug: match[5] } : {}
            end
          end

          # The technical name: the declared slug, else the title's.
          def slug
            title = declaration[:title]
            declaration[:slug] || (title && BoardDefinition.slug(title))
          end

          # The prefix of the board's environment variables.
          def env_prefix = slug && "#{slug.upcase.tr('-', '_')}_"
        end

        # The camel-case class name of the file +path+ (<tt>feed_model.rb</tt> →
        # +FeedModel+, +bbs+ and +ttg+ in capitals).
        def self.class_name(path)
          File.basename(path, '.rb').split('_').map { |w| %w[bbs ttg].include?(w) ? w.upcase : w.capitalize }.join
        end
      end
    end
  end
end

require_relative 'check/rules'
