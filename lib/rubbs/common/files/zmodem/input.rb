# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Zmodem
        # The receiver's side of the line as the Sender reads it: its bytes
        # (telnet commands taken out by the session) kept until they make a
        # header, at most MAX_PENDING of them; five CANs in a row cancel.
        class Input
          # Reads from +session+ (anything with Rubbs::Common::Line::Telnet#read_raw_byte).
          def initialize(session)
            @session = session
            @pending = []
            @cans    = 0
          end

          # Waits up to +timeout+ seconds for a header of one of +types+ and
          # returns it, skipping others. Raises Cancelled when the receiver gives
          # up, Timeout when nothing came (unless +ignore_timeout+: +nil+ then),
          # Hangup when the line dropped.
          def expect(*types, timeout: WAIT, ignore_timeout: false)
            deadline = monotonic + timeout
            loop do
              header = read_header(timeout: deadline - monotonic)
              return if header.nil? && ignore_timeout
              raise Timeout if header.nil?
              raise Cancelled if [ZCAN, ZABORT, ZFERR].include?(header.type)
              return header if types.include?(header.type)
            end
          end

          # Takes what the receiver has sent so far without waiting, and returns
          # the header it makes, if any.
          def poll_header
            while (byte = @session.read_raw_byte(0)).is_a?(Integer)
              push(byte)
            end
            raise Hangup if byte.nil?

            scan_pending
          end

          # Waits up to +timeout+ seconds for a header and returns it, or +nil+.
          # With +interruptible+ the caller's Esc or Ctrl-C raises Cancelled.
          def read_header(timeout:, interruptible: false)
            deadline = monotonic + timeout
            loop do
              header = scan_pending
              return header if header

              byte = next_byte(deadline - monotonic) or return
              raise Cancelled if interruptible && CANCEL_KEYS.include?(byte)

              push(byte)
            end
          end

          private

          # The next byte within +left+ seconds; +nil+ when none came.
          def next_byte(left)
            return unless left.positive?

            byte = @session.read_raw_byte(left)
            raise Hangup if byte.nil?

            byte unless byte == :timeout
          end

          def push(byte)
            @cans = byte == ZDLE ? @cans + 1 : 0
            raise Cancelled if @cans >= CANCEL_COUNT

            @pending << byte
            @pending.shift(@pending.size - MAX_PENDING) if @pending.size > MAX_PENDING
          end

          def scan_pending
            while (start = @pending.index(ZPAD))
              @pending.shift(start)
              header, used = Frames.parse(@pending)
              return if used.nil?

              @pending.shift(used)
              return header if header
            end
            @pending.clear
            nil
          end

          def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
