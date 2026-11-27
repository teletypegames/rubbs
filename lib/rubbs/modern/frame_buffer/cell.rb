# frozen_string_literal: true

module Rubbs
  module Modern
    class FrameBuffer
      # One screen cell: +char+ is the character shown, +sgr+ the SGR escape
      # sequence that styles it (+nil+ for the terminal default).
      Cell = Struct.new(:char, :sgr) do
        # The frozen Cell of +char+ in style +sgr+, one per pair: a frame is
        # redrawn every second (the clock, a chat) and mostly holds the same
        # cells, so they are shared rather than made again, and two frames
        # compare cell by cell by identity. The table starts over once it
        # holds CACHE_LIMIT cells.
        def self.of(char, sgr)
          row = (CACHE[sgr] ||= {})
          row[char] || remember(row, char, sgr)
        end

        # Keeps a new frozen Cell in +row+ of the table and returns it.
        def self.remember(row, char, sgr)
          if (@count = @count.to_i + 1) > CACHE_LIMIT
            CACHE.clear
            @count = 1
            row = (CACHE[sgr] ||= {})
          end
          row[char] = new(-char, sgr && -sgr).freeze
        end
      end
      # The shared cells of Cell.of, by style and then character.
      CACHE = {} # rubocop:disable Style/MutableConstant
      # How many cells Cell.of keeps before it starts over.
      CACHE_LIMIT = 20_000
    end
  end
end
