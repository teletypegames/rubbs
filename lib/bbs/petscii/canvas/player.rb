# frozen_string_literal: true

module BBS
  module Petscii
    class Canvas
      # Plays PETSCII onto a Canvas the way the C64's screen editor prints
      # it: what a C64 shows after a #frame, #span or #patch, for tests and
      # previews.
      module Player
        # What a control code does, by code: the method that plays it.
        CONTROLS = {
          CLEAR     => :wipe,
          HOME      => :home,
          RVS_ON    => :rvs_on,
          RVS_OFF   => :rvs_off,
          CR        => :newline,
          UPPERCASE => :upper,
          LOWERCASE => :lower,
          DOWN      => :down,
          UP        => :up,
          RIGHT     => :advance,
          LEFT      => :back
        }.freeze
        # The codes the screen editor prints.
        PRINTED = [0x20..0x7f, 0xa0..0xff].freeze

        # Plays +bytes+ (PETSCII, a String) onto the screen: colours,
        # reverse video, CLR, HOME, the cursor keys, RETURN, the character
        # set switches and printable codes; the cursor wraps at the end of a
        # row and the screen scrolls at the bottom. Other codes are skipped.
        # The cursor, colour and reverse state carry over to the next call.
        #
        # Returns +self+.
        def feed(bytes)
          bytes.to_s.each_byte { |b| play(b) }
          self
        end

        private

        def play(byte)
          return @pen = byte if RGB.key?(byte)
          return send(CONTROLS[byte]) if CONTROLS.key?(byte)

          print_code(byte) if PRINTED.any? { |range| range.cover?(byte) }
        end

        def wipe
          @cells = Array.new(ROWS) { Array.new(COLS) { blank } }
          home
        end

        def home = @at = [0, 0]

        def rvs_on = @rvs = true

        def rvs_off = @rvs = false

        def upper = @charset = :upper

        def lower = @charset = :lower

        def up = (@at[0] -= 1 if @at[0].positive?)

        def down = @at[0] == ROWS - 1 ? scroll : @at[0] += 1

        def newline
          rvs_off
          @at[1] = 0
          down
        end

        def print_code(byte)
          @cells[@at[0]][@at[1]] = Cell.new(byte, @pen, @rvs)
          advance
        end

        def advance
          @at[1] += 1
          return if @at[1] < COLS

          @at[1] = 0
          down
        end

        def back
          if @at[1].positive?
            @at[1] -= 1
          elsif @at[0].positive?
            @at = [@at[0] - 1, COLS - 1]
          end
        end

        def scroll
          @cells.shift
          @cells << Array.new(COLS) { blank }
        end
      end

      include Player
    end
  end
end
