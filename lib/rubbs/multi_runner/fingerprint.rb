# frozen_string_literal: true

require 'digest'

module Rubbs
  class MultiRunner
    # What a board's code looks like now, as one digest: the paths and the
    # contents of its files, less what does not run (IGNORED). Contents, not
    # times: a deploy that writes every file anew changes nothing here unless
    # a file did change.
    module Fingerprint
      # Top-level folders and files of a board that are not its code: its
      # data, its tests, its notes.
      IGNORED = %w[data test tmp log].freeze
      # File names that are not code either.
      IGNORED_FILES = /\.(md|txt)\z/i

      # The digest (a hex String) of the board in +dir+; +nil+ when the
      # folder is gone.
      def self.of(dir)
        return nil unless File.directory?(dir)

        digest = Digest::SHA256.new
        files(dir).each do |path|
          digest << path << "\0" << Digest::SHA256.file(File.join(dir, path)).digest
        rescue SystemCallError
          next
        end
        digest.hexdigest
      end

      # The code files of +dir+, relative and sorted.
      def self.files(dir)
        Dir.glob('**/*', File::FNM_DOTMATCH, base: dir).sort.select do |path|
          next false if IGNORED.include?(path.split('/').first) || path.match?(IGNORED_FILES)

          File.file?(File.join(dir, path))
        end
      end
    end
  end
end
