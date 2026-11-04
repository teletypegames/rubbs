# frozen_string_literal: true

module BBS
  module Check
    # The forms rubbs 2 replaced, each with what to write instead
    # (UPGRADING.md has the whole story).
    OLD_FORMS = {
      /\bBBS\.configure\b/ => 'BBS.board says it (bbs.rb)',
      /\bTerminal\.flow\b/ => 'BBS.board builds the terminal question',
      /\bGoodbye\.(?:modern|petscii|show)\(\s*runner/ => 'BBS.board says goodbye (goodbye … in bbs.rb)',
      /rescue\s+IOError\s*,\s*Errno::EPIPE/ => 'a dropped line ends the call by itself (BBS::Hangup)',
      /\bColors\.install\b/ => 'a BBS::Petscii::Face has the colours',
      /\bctx\[:app\]/ => 'window blocks run in the application',
      /\bwith_loading\b/ => 'loading(…, failed: …)',
      /\bstatus_hint\b/ => 'command(…, key:)',
      /\bmenubar\s+do\b/ => "menu 'Name', :command, …",
      /\btitle:\s*' [^']+ '/ => 'titles are plain; the frame pads them',
      /\bRateLimit\.caller_key\(/ => 'session.caller_key / caller_key',
      /\bwindow\([^)]*type:\s*:/ => 'window :name, :type do … end',
      /\braise IOError,\s*['"][^'"]*hung up/ => 'raise BBS::Hangup'
    }.freeze

    # The layers of a board's domain, each a folder of lib/domain.
    LAYERS = %w[model repository service].freeze

    rule(:layout, 'the files and folders of a rubbs board') do |board|
      %w[bbs.rb Rakefile Gemfile Gemfile.lock README.md lib/domain.rb].each do |path|
        board.fail(path, 'missing') unless board.file?(path)
      end
      board.fail('test/test_helper.rb', 'missing') if board.glob('test/**/test_helper.rb').empty?
      LAYERS.each { |layer| board.fail("lib/domain/#{layer}/", 'missing') unless board.dir?("lib/domain/#{layer}") }
    end

    rule(:bbs_rb, 'bbs.rb is requires and one BBS.board declaration') do |board|
      lines = board.read('bbs.rb').to_s.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
      start = lines.index { |l| l.start_with?('BBS.board ') }
      next board.fail('bbs.rb', 'no BBS.board declaration') unless start

      extra = lines[0...start].grep_v(/\Arequire(?:_relative)?\s/)
      board.fail('bbs.rb', "only requires before BBS.board, not: #{extra.first}") if extra.any?
      board.fail('bbs.rb', 'nothing after the BBS.board declaration') unless lines.last == 'end' || lines.size == start + 1
    end

    rule(:domain, 'the domain object is a BBS::Domain, the only place that reads ENV') do |board|
      roots = board.glob('lib/domain/*.rb').select { |path| board.read(path).include?('include BBS::Domain') }
      board.fail('lib/domain/', 'no domain object (a class that includes BBS::Domain)') if roots.empty?
      board.glob('lib/ui/**/*.rb').each do |path|
        board.fail(path, 'reads ENV: make it a setting of the domain object') if board.read(path).match?(/\bENV\b/)
      end
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
