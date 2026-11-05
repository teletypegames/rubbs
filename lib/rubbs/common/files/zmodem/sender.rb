# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Zmodem
        # One ZMODEM batch send over a session. Zmodem.send_files is the usual
        # way in.
        class Sender
          # Creates a sender writing to and reading raw bytes from +session+;
          # +telnet+ doubles 0xFF bytes as telnet IAC.
          def initialize(session, telnet: true)
            @in     = Input.new(session)
            @out    = Output.new(session, telnet: telnet)
            @window = 0
          end

          # Sends +files+ (as for Zmodem.send_files): writes +rz+ and CR, waits
          # up to +wait+ seconds for ZRINIT, offers and streams each file, then
          # ends the session with ZFIN. Writes the abort sequence on cancel or
          # timeout.
          #
          # Returns +:ok+, +:cancelled+, +:timeout+ or +:hangup+.
          def run(files, wait:)
            files = files.map { |name, data, mtime| [File.basename(name.to_s), data.to_s.b, mtime || Time.now] }
            @out.emit(RZ_COMMAND)
            handshake(wait)
            files.each_with_index { |file, i| send_file(*file, files[i..]) }
            finish
          rescue Cancelled, Timeout => e
            @out.emit(ABORT)
            e.is_a?(Cancelled) ? :cancelled : :timeout
          rescue Hangup, IOError, SystemCallError
            :hangup
          end

          private

          def handshake(wait)
            deadline = monotonic + wait
            loop do
              @out.hex_header(ZRQINIT, [0, 0, 0, 0])
              header = @in.read_header(timeout: [ANSWER_WAIT, deadline - monotonic].min, interruptible: true)
              return receiver(header) if header&.type == ZRINIT
              raise Timeout if monotonic >= deadline
            end
          end

          # What the receiver's ZRINIT says it can: CRC-32, and the bytes it
          # takes before an acknowledgement (0: any).
          def receiver(header)
            @out.crc32 = header.flags.to_i.anybits?(CANFC32)
            @window    = header.bytes[0] | (header.bytes[1] << 8)
          end

          def send_file(name, data, mtime, rest)
            info = "#{name}#{Line::Ascii::NUL_CHAR}#{data.bytesize} #{mtime.to_i.to_s(8)} #{FILE_MODE} 0 #{rest.size} " \
                   "#{rest.sum { |f| f[1].bytesize }}#{Line::Ascii::NUL_CHAR}".b
            FILE_TRIES.times do
              @out.offer(info)
              header = @in.expect(ZRPOS, ZSKIP, ZCRC, ZNAK, timeout: ANSWER_WAIT, ignore_timeout: true)
              return offered(data, header) if header && header.type != ZNAK
            end
            raise Timeout
          end

          # The receiver's answer to a file: ZRPOS streams it, ZCRC asks for its
          # CRC first, ZSKIP skips it.
          def offered(data, header)
            case header.type
            when ZRPOS then Stream.new(@in, @out, @window).send_file(data, header.position)
            when ZCRC
              @out.hex_header(ZCRC, [Zlib.crc32(data)].pack('V').bytes)
              offered(data, @in.expect(ZRPOS, ZSKIP))
            end
          end

          def finish
            @out.hex_header(ZFIN, [0, 0, 0, 0])
            @in.read_header(timeout: FIN_WAIT)
            @out.emit(OVER_AND_OUT)
            :ok
          end

          def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
