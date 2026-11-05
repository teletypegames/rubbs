# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      module Check
        # The forms rubbs 2 replaced, each with what to write instead
        # (UPGRADING.md has the whole story).
        OLD_FORMS = {
          /\b(?:BBS|Rubbs)\.configure\b/                  => 'Rubbs.board says it (bbs.rb)',
          /\bTerminal\.flow\b/                            => 'Rubbs.board builds the terminal question',
          /\bGoodbye\.(?:modern|petscii|show)\(\s*runner/ => 'Rubbs.board says goodbye (goodbye … in bbs.rb)',
          /rescue\s+IOError\s*,\s*Errno::EPIPE/           => 'a dropped line ends the call by itself (Rubbs::Common::Line::Hangup)',
          /\bColors\.install\b/                           => 'a Rubbs::Petscii::Face has the colours',
          /\bctx\[:app\]/                                 => 'window blocks run in the application',
          /\bwith_loading\b/                              => 'loading(…, failed: …)',
          /\bstatus_hint\b/                               => 'command(…, key:)',
          /\bmenubar\s+do\b/                              => "menu 'Name', :command, …",
          /\btitle:\s*' [^']+ '/                          => 'titles are plain; the frame pads them',
          /\bRateLimit\.caller_key\(/                     => 'session.caller_key / caller_key',
          /\bwindow\([^)]*type:\s*:/                      => 'window :name, :type do … end',
          /\braise IOError,\s*['"][^'"]*hung up/          => 'raise Rubbs::Common::Line::Hangup',
          /\bBBS::SQLite\b/                               => 'a Rubbs::Common::Storage::Model for each table (rubbs 2.3)'
        }.freeze

        # The layers of a board's domain, each a folder of lib/domain; a board
        # with no outside source (HTTP, files) has no repository.
        LAYERS = %w[model repository service].freeze
        # The layers every board has.
        REQUIRED_LAYERS = %w[model service].freeze

        rule(:layout, 'the files and folders of a rubbs board') do |board|
          %w[bbs.rb Rakefile Gemfile Gemfile.lock README.md lib/domain.rb].each do |path|
            board.fail(path, 'missing') unless board.file?(path)
          end
          board.fail('test/test_helper.rb', 'missing') if board.glob('test/**/test_helper.rb').empty?
          REQUIRED_LAYERS.each { |layer| board.fail("lib/domain/#{layer}/", 'missing') unless board.dir?("lib/domain/#{layer}") }
        end

        rule(:bbs_rb, 'bbs.rb is requires and one Rubbs.board declaration') do |board|
          lines = board.read('bbs.rb').to_s.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
          start = lines.index { |l| l.start_with?('Rubbs.board ') }
          next board.fail('bbs.rb', 'no Rubbs.board declaration') unless start

          extra = lines[0...start].grep_v(/\Arequire(?:_relative)?\s/)
          board.fail('bbs.rb', "only requires before Rubbs.board, not: #{extra.first}") if extra.any?
          board.fail('bbs.rb', 'nothing after the Rubbs.board declaration') unless lines.last == 'end' || lines.size == start + 1
        end

        rule(:domain, 'the domain object is a Rubbs::Common::Board::Domain, the only place that reads ENV') do |board|
          roots = board.glob('lib/domain/*.rb').select { |path| board.read(path).include?('include Rubbs::Common::Board::Domain') }
          board.fail('lib/domain/', 'no domain object (a class that includes Rubbs::Common::Board::Domain)') if roots.empty?
          board.glob('lib/ui/**/*.rb').each do |path|
            board.fail(path, 'reads ENV: make it a setting of the domain object') if board.read(path).match?(/\bENV\b/)
          end
        end

        rule(:env_prefix, "the domain class reads the board's variables without Rubbs.board too") do |board|
          domain = board.declaration[:domain]
          next unless domain && board.env_prefix

          derived = "#{domain.gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2').gsub(/([a-z\d])([A-Z])/, '\\1_\\2').upcase}_"
          next if derived == board.env_prefix

          declared = board.glob('lib/domain/*.rb').any? do |path|
            board.read(path).match?(/^\s*env_prefix\s+['"]#{Regexp.escape(board.env_prefix)}['"]/)
          end
          next if declared

          board.fail('lib/domain/', "#{domain} reads #{derived}* outside Rubbs.board: say env_prefix '#{board.env_prefix}'")
        end

        rule(:names, 'each domain file defines the class of its name') do |board|
          LAYERS.each do |layer|
            board.glob("lib/domain/**/#{layer}/*.rb").each do |path|
              name = Check.class_name(path)
              unless board.read(path).match?(/(?:class|module)\s+(?:\w+::)*#{name}\b|\b#{name}\s*=/)
                board.fail(path, "defines no #{name}")
              end
            end
          end
        end

        rule(:faces, 'a modern and a C64 face in lib/ui') do |board|
          next if board.options[:faces] == false

          %w[lib/ui/modern.rb lib/ui/petscii.rb].each { |path| board.fail(path, 'missing') unless board.file?(path) }
        end

        rule(:wording, 'the texts the faces share are UI::Wording in lib/ui/wording.rb') do |board|
          board.glob('lib/ui/*.rb').each do |path|
            next unless File.basename(path).match?(/\A(?:words|texts?|messages|strings|.+_text)\.rb\z/)

            board.fail(path, 'a text table is lib/ui/wording.rb (UI::Wording)')
          end
        end

        rule(:tests, 'tests are test/**/*_test.rb and load the test helper') do |board|
          tests = board.glob('test/**/*_test.rb')
          board.fail('test/', 'no tests') if tests.empty?
          tests.each do |path|
            unless board.read(path).match?(%r{require(?:_relative)?\s+['"](?:\./)?(?:\.\./)*test_helper['"]})
              board.fail(path, "does not require 'test_helper'")
            end
          end
        end

        # SQL in a string: what only the model layer and the migrations write.
        # (A SPARQL query, <tt>SELECT ?item …</tt>, and a constant named
        # +SELECT+ are not SQL.)
        SQL = /
          (?:['"]|^)\s*
          (?:SELECT(?!\s*=|\s+(?:DISTINCT\s+)?\?)|INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM|
             CREATE\s+(?:TABLE|INDEX)|ALTER\s+TABLE)\b
        /x
        # The files where SQL is at home.
        SQL_HOMES = %r{\Alib/domain/(?:.*/)?(?:model/|migrations\.rb\z)}

        # A table made by SQL or by Sequel's create_table.
        TABLE = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?(\w+)|create_table\??\(:(\w+)/i

        rule(:models, 'every table has its Rubbs::Common::Storage::Model in lib/domain/model') do |board|
          tables   = board.glob('lib/**/*.rb').flat_map { |path| board.read(path).scan(TABLE).map(&:compact).flatten }
          modelled = board.glob('lib/domain/**/model/*.rb').flat_map do |path|
            board.read(path).scan(/^\s*table\s+:(\w+)/).flatten
          end
          (tables.uniq - modelled).each do |table|
            board.fail('lib/domain/model/', "the table #{table} has no model (table :#{table})")
          end
          if modelled.any? && !board.file?('lib/domain/migrations.rb')
            board.fail('lib/domain/migrations.rb', 'missing: the migrations of the models')
          end
        end

        rule(:raw_sql, 'SQL only in the model layer and lib/domain/migrations.rb') do |board|
          board.ruby_files.grep_v(SQL_HOMES).each do |path|
            board.fail(path, 'SQL outside the model layer: a method of the model') if board.read(path).match?(SQL)
          end
        end

        rule(:old_forms, 'none of the forms rubbs 2 replaced') do |board|
          board.ruby_files.each do |path|
            text = board.read(path)
            OLD_FORMS.each { |pattern, instead|
              board.fail(path, "old form #{pattern.source[0, 30]}: #{instead}") if text.match?(pattern)
            }
          end
        end
      end
    end
  end
end
