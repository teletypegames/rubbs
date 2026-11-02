# frozen_string_literal: true

module BBS
  module Zmodem
    # The data of one file going out: subpackets streamed from a position,
    # waiting for a ZACK when the receiver's window is full, and sent again
    # from where a ZRPOS asks.
    class Stream
      # Streams over +input+ (an Input) and +output+ (an Output) to a
      # receiver that takes +window+ bytes before an acknowledgement (0:
      # any).
      def initialize(input, output, window)
        @in     = input
        @out    = output
        @window = window
      end

      # Sends +data+ from +pos+ and its end, again from where the receiver
      # asks, at most RESTARTS times and BUDGET_FACTOR times its size.
      # Raises Cancelled past those, as the Sender's errors otherwise.
      def send_file(data, pos)
        @budget = BUDGET_FACTOR * [data.bytesize, SUBPACKET].max
        RESTARTS.times do
          pos = send_data(data, pos) || end_of_file(data, pos)
          return if pos == :done
        end
        raise Cancelled
      end

      private

      # :done when the receiver took the file, else where to send from.
      def end_of_file(data, pos)
        @out.position_header(ZEOF, data.bytesize)
        header = @in.expect(ZRINIT, ZRPOS, ZNAK)
        case header.type
        when ZRINIT then :done
        when ZRPOS  then header.position
        else pos
        end
      end

      # The subpackets from +pos+ to the end: nil when all went out, the
      # position the receiver asked for (ZRPOS) when it wants them again.
      def send_data(data, pos)
        pos = pos.clamp(0, data.bytesize)
        return if pos == data.bytesize

        @start = @acked = pos
        @out.position_header(ZDATA, pos)
        while pos < data.bytesize
          chunk = spend(data.byteslice(pos, SUBPACKET))
          pos  += chunk.bytesize
          again = send_chunk(chunk, pos, pos >= data.bytesize)
          return again if again
        end
      end

      # Sends one subpacket ending at +pos+ (+last+ of the file or not);
      # returns the position the receiver asks for again, or +nil+.
      def send_chunk(chunk, pos, last)
        return acknowledged(chunk, pos) if !last && @window.positive? && pos - @acked >= @window

        @out.subpacket(chunk, last ? ZCRCE : ZCRCG)
        rewind
      end

      # A full window waits for the receiver's ZACK.
      def acknowledged(chunk, pos)
        @out.subpacket(chunk, ZCRCW)
        header = @in.expect(ZACK, ZRPOS)
        return header.position if header.type == ZRPOS

        @acked = pos
        rewind
      end

      # Where the receiver asks to start again, when it does.
      def rewind
        header = @in.poll_header
        header.position if header&.type == ZRPOS && header.position != @start
      end

      def spend(chunk)
        @budget -= chunk.bytesize
        raise Cancelled if @budget.negative?

        chunk
      end
    end
  end
end
