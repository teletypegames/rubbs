# frozen_string_literal: true

module Rubbs
  class MultiRunner
    # A board for a Rubbs::MultiRunner: its +name+ (the folder's) and its
    # folder (+dir+), with the +bbs.rb+ that declares it, or a +definition+
    # already made (a Rubbs::Common::Board::BoardDefinition, its folder the
    # current one).
    BoardRef = Data.define(:name, :dir, :definition) do
      # The board in the folder +dir+.
      def self.at(dir)
        dir = File.expand_path(dir)
        new(name: File.basename(dir), dir: dir, definition: nil)
      end

      # +board+ as a BoardRef: a BoardRef as it is, a
      # Rubbs::Common::Board::BoardDefinition with the current folder, a
      # folder name (String) by #at.
      def self.of(board)
        case board
        when BoardRef then board
        when String then at(board)
        else new(name: board.slug, dir: Dir.pwd, definition: board)
        end
      end

      # The board's declaration file.
      def file = File.join(dir, 'bbs.rb')

      # The Rubbs::Common::Board::BoardDefinition: the one given, else the one
      # the +bbs.rb+ declares (loaded now, so only in the board's process).
      # Raises ArgumentError when the file declares none.
      def load_definition
        return definition if definition

        MultiRunner.capture { load file } or raise ArgumentError, "#{file} declares no Rubbs.board"
      end
    end
  end
end
