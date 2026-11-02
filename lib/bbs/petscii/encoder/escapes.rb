# frozen_string_literal: true

module BBS
  module Petscii
    class Encoder
      # The ANSI escape sequences an Encoder reads: CSI cursor moves, the
      # screen erase and SGR (handed to Sgr); character set designations
      # are skipped.
      module Escapes
        # What a CSI sequence does, by its final byte: the method that
        # handles it.
        CSI_ACTIONS = {
          'm' => :csi_sgr, 'J' => :csi_erase, 'H' => :csi_position, 'f' => :csi_position,
          'A' => :csi_up, 'B' => :csi_down, 'C' => :csi_right, 'D' => :csi_left, 'G' => :csi_column
        }.freeze
        # The bytes that start an escape sequence the Encoder reads: CSI, and
        # the character set designations it skips.
        ESCAPE_STARTS = ['[', '(', ')'].freeze

        private

        # One more character of the escape sequence being read: a CSI
        # sequence acts when its final byte comes; one too long, or a
        # character set designation, is dropped.
        def escape(ch, out)
          return @esc = (ESCAPE_STARTS.include?(ch) ? +ch : nil) if @esc.empty?
          return @esc = nil if @esc.start_with?('(', ')')

          @esc << ch
          return @esc = nil if @esc.length > Ansi::MAX_CSI_LENGTH

          finish_csi(ch, out) if ch.match?(ESCAPE_FINAL)
        end

        def finish_csi(final, out)
          params = @esc[1...-1]
          @esc   = nil
          action = CSI_ACTIONS[final]
          send(action, params.delete('?').split(';').map(&:to_i), out) if action
        end

        def count(nums) = [nums.first.to_i, 1].max

        def csi_sgr(nums, out) = sgr(nums.empty? ? [0] : nums, out)

        def csi_erase(nums, out)
          clear(out) if nums.first == 2
        end

        def csi_position(nums, out)
          row = [nums[0].to_i, 1].max
          col = [nums[1].to_i, 1].max
          home(out)
          out << bytes(DOWN * (row - 1)) << bytes(RIGHT * (col - 1))
          move(col - 1)
        end

        def csi_up(nums, out) = out << bytes(UP * count(nums))

        def csi_down(nums, out) = out << bytes(DOWN * count(nums))

        def csi_right(nums, out)
          out << bytes(RIGHT * count(nums))
          move(count(nums))
        end

        def csi_left(nums, out)
          out << bytes(LEFT * count(nums))
          move(-count(nums))
        end

        def csi_column(nums, out)
          n = count(nums)
          out << bytes("#{Ansi::CR}#{UP}#{RIGHT * (n - 1)}") unless @wrapped && n == 1
          @col = 0
          move(n - 1)
        end
      end

      include Escapes
    end
  end
end
