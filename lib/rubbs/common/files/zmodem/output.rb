# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      module Zmodem
        # The Sender's side of the line: headers and data subpackets framed,
        # escaped and checked with a CRC-16, or a CRC-32 once the receiver said
        # it can (#crc32=), and 0xFF doubled as telnet IAC on a telnet line.
        class Output
          # Whether frames carry a CRC-32 instead of a CRC-16.
          attr_writer :crc32

          # Writes to +session+ (anything with +write_raw+); +telnet+ doubles
          # 0xFF.
          def initialize(session, telnet:)
            @session = session
            @telnet  = telnet
            @crc32   = false
          end

          # Writes a hex header of +type+ with the four +bytes+.
          def hex_header(type, bytes)
            frame = [type, *bytes].pack('C*')
            hex   = (frame + [Zmodem.crc16(frame)].pack('n')).unpack1('H*')
            tail  = [ZFIN, ZACK].include?(type) ? '' : XON.chr
            emit("#{HEX_HEADER}#{hex}#{Modern::Ansi::CRLF}#{tail}".b)
          end

          # Writes a binary header of +type+ with the four +bytes+.
          def bin_header(type, bytes)
            frame = [type, *bytes].pack('C*')
            emit(BIN_HEADER + (@crc32 ? ZBIN32 : ZBIN).chr + Zmodem.escape(frame + crc(frame)))
          end

          # Writes a binary header of +type+ whose data is the file position
          # +pos+.
          def position_header(type, pos) = bin_header(type, [pos].pack('V').bytes)

          # Offers a file: a ZFILE header and its +info+ subpacket (name, size,
          # time, mode and what is left of the batch).
          def offer(info)
            bin_header(ZFILE, [0, 0, 0, ZCBIN])
            subpacket(info, ZCRCW)
          end

          # Writes +data+ as a subpacket ending in +frameend+ (ZCRCE, ZCRCG or
          # ZCRCW, which wants an XON after it).
          def subpacket(data, frameend)
            out = Zmodem.escape(data) << ZDLE << frameend << Zmodem.escape(crc(data + frameend.chr))
            out << XON if frameend == ZCRCW
            emit(out)
          end

          # Writes +bytes+ as they are (IAC doubled on a telnet line).
          def emit(bytes)
            @session.write_raw(@telnet ? bytes.b.gsub(TELNET_IAC, TELNET_IAC * 2) : bytes)
          end

          private

          def crc(bytes) = @crc32 ? [Zlib.crc32(bytes)].pack('V') : [Zmodem.crc16(bytes)].pack('n')
        end
      end
    end
  end
end
