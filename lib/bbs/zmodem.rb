# frozen_string_literal: true

require 'zlib'

module BBS
  # ZMODEM downloads: the sending side of Chuck Forsberg's protocol, enough
  # for the caller's terminal to save files from the BBS: SyncTERM,
  # NetRunner, Qodem, lrzsz's +rz+ behind a plain telnet, or zmodem.js in a
  # web terminal.
  #
  #   BBS::Zmodem.send_files(session, [['README.TXT', bytes, Time.now]])
  #   # => :ok, :cancelled, :timeout or :hangup
  #
  # Every control character goes out ZDLE-escaped, so the stream holds no
  # bare CR and needs no telnet BINARY mode, and 0xFF goes out as a doubled
  # telnet IAC (<tt>telnet: false</tt> for a plain byte pipe). While it waits
  # for the terminal to answer, Esc or Ctrl-C gives up.
  module Zmodem
    # Frame padding character (<tt>*</tt>) that starts every header.
    ZPAD   = 0x2a
    # ZMODEM data link escape (Ctrl-X): prefixes escaped bytes and header
    # formats; five in a row cancel the transfer.
    ZDLE   = 0x18
    # Header format byte: binary header with a CRC-16.
    ZBIN   = 0x41
    # Header format byte: hex header with a CRC-16.
    ZHEX   = 0x42
    # Header format byte: binary header with a CRC-32.
    ZBIN32 = 0x43
    # XON (Ctrl-Q), sent after hex headers and ZCRCW subpackets to restart
    # a receiver that uses software flow control.
    XON    = 0x11

    # Header type: sender asks the receiver to send ZRINIT.
    ZRQINIT = 0
    # Header type: receiver is ready; carries its buffer size and
    # capability flags.
    ZRINIT  = 1
    # Header type: acknowledges a ZCRCW subpacket.
    ZACK    = 3
    # Header type: file name and size follow in a subpacket.
    ZFILE   = 4
    # Header type: receiver skips the offered file.
    ZSKIP   = 5
    # Header type: last header was garbled, send it again.
    ZNAK    = 6
    # Header type: receiver aborts the batch.
    ZABORT  = 7
    # Header type: end of the session.
    ZFIN    = 8
    # Header type: receiver asks for data from the given file position.
    ZRPOS   = 9
    # Header type: data subpackets follow from the given position.
    ZDATA   = 10
    # Header type: end of file at the given position.
    ZEOF    = 11
    # Header type: receiver hit a fatal file error.
    ZFERR   = 12
    # Header type: request for, or answer with, the file's CRC-32.
    ZCRC    = 13
    # Header type: the other side cancelled the transfer.
    ZCAN    = 16

    # Subpacket end: CRC follows, frame ends, no answer expected.
    ZCRCE = 0x68
    # Subpacket end: CRC follows, more data comes without waiting.
    ZCRCG = 0x69
    # Subpacket end: CRC follows, the receiver must answer with ZACK.
    ZCRCW = 0x6b

    # ZRINIT capability flag: the receiver understands CRC-32 frames.
    CANFC32 = 0x20
    # ZFILE conversion option: binary transfer, no line-end conversion.
    ZCBIN   = 1

    # Bytes of file data per data subpacket.
    SUBPACKET = 1024
    # The abort sequence: eight Ctrl-X followed by eight backspaces, which
    # makes the receiver drop the transfer and erases the echo.
    ABORT     = ((ZDLE.chr * 8) + (Ascii::BS.chr * 8)).b

    # The command that starts the receiver on a Unix shell: +rz+ and CR.
    RZ_COMMAND   = "rz#{Ansi::CR}".b.freeze
    # What starts a hex header: two ZPAD, ZDLE and ZHEX.
    HEX_HEADER   = [ZPAD, ZPAD, ZDLE, ZHEX].pack('C*').freeze
    # What starts a binary header, before ZBIN or ZBIN32: ZPAD and ZDLE.
    BIN_HEADER   = [ZPAD, ZDLE].pack('C*').freeze
    # "Over and out", the sender's last word after ZFIN.
    OVER_AND_OUT = 'OO'.b.freeze
    # The Unix file mode sent in the ZFILE header, in octal.
    FILE_MODE    = '100644'
    # The telnet IAC byte, doubled in the data on a telnet line.
    TELNET_IAC   = Telnet::IAC.chr.b.freeze

    # The CRC-16/XMODEM polynomial.
    CRC16_POLY = 0x1021
    # The top bit of a CRC-16, shifted out before the polynomial is added.
    CRC16_TOP  = 0x8000
    # The bits of a CRC-16.
    CRC16_MASK = 0xffff
    # The bytes of a CRC-16 after a header or subpacket.
    CRC16_SIZE = 2
    # The bytes of a CRC-32 after a header or subpacket.
    CRC32_SIZE = 4
    # The C0 control bytes, sent escaped.
    ESCAPED_C0 = 0x00..0x1f
    # The C1 control bytes, sent escaped.
    ESCAPED_C1 = 0x80..0x9f
    # XORed into an escaped byte after ZDLE.
    ZDLE_XOR   = 0x40
    # ZRUB0: ZDLE and this byte stand for ZRUB0_VALUE.
    ZRUB0      = 0x6c
    # The byte ZRUB0 stands for: DEL.
    ZRUB0_VALUE = 0x7f
    # ZRUB1: ZDLE and this byte stand for ZRUB1_VALUE.
    ZRUB1 = 0x6d
    # The byte ZRUB1 stands for.
    ZRUB1_VALUE = 0xff
    # The bytes of a header before its CRC: the type and four data bytes.
    HEADER_SIZE = 5
    # The hex digits of a hex header after ZHEX: type, data and CRC-16.
    HEX_DIGITS  = 14
    # A hex header's digits.
    HEX_HEADER_RE = /\A\h{14}\z/

    # The keys the caller cancels the start of a transfer with: Esc and
    # Ctrl-C.
    CANCEL_KEYS  = [Ascii::ESC, Ascii::ETX].freeze
    # The ZDLE (CAN) bytes in a row that cancel the transfer.
    CANCEL_COUNT = 5
    # Times a ZFILE header is sent before the file is given up.
    FILE_TRIES   = 5
    # Seconds to wait for the receiver's answer, by default.
    WAIT         = 30
    # Seconds to wait for one answer to ZRQINIT or ZFILE.
    ANSWER_WAIT  = 10
    # Seconds to wait for the receiver's ZFIN.
    FIN_WAIT     = 5
    # The most times a file is sent again from where the receiver asks
    # (ZRPOS) before the transfer is given up.
    RESTARTS     = 16
    # The most bytes of a file sent, counting the restarts, as a multiple of
    # its size (or of SUBPACKET for a smaller file); past it the transfer is
    # given up.
    BUDGET_FACTOR = 4
    # The most bytes of the receiver kept while looking for a header; older
    # ones are dropped.
    MAX_PENDING = 64

    # The bytes a ZDLE escape stands for when it is not the byte XOR 0x40.
    ZDLE_VALUES = { ZRUB0 => ZRUB0_VALUE, ZRUB1 => ZRUB1_VALUE }.freeze

    # A parsed ZMODEM header: +type+ is the header type (ZRINIT, ZRPOS, ...),
    # +bytes+ the four data bytes.
    Header = Struct.new(:type, :bytes) do
      # The data bytes read as a little-endian file offset.
      def position = bytes.each_with_index.sum { |b, i| b << (8 * i) }
      # The fourth data byte (ZF0).
      def flags    = bytes[3]
    end

    # Raised inside the sender when the caller or the terminal cancels.
    class Cancelled < StandardError; end
    # Raised inside the sender when the terminal does not answer in time.
    class Timeout < StandardError; end
    # Raised inside the sender when the line drops.
    class Hangup < StandardError; end

    module_function

    # Sends +files+ to the caller's terminal over +session+.
    #
    # [session] the BBS::Session to send on
    # [files]   an Array of <tt>[name, data]</tt> or <tt>[name, data, mtime]</tt>;
    #           only the base name of +name+ is sent, +mtime+ defaults to now
    # [wait]    seconds to wait for a ZMODEM receiver to answer
    # [telnet]  double 0xFF bytes as telnet IAC; +false+ for a plain byte pipe
    #
    # Returns +:ok+ when the terminal took the files (or skipped some),
    # +:cancelled+ when the caller or the terminal gave up (or the terminal
    # asked for a file again more than RESTARTS times or for more than
    # BUDGET_FACTOR times its bytes), +:timeout+ when
    # no receiver answered within +wait+ seconds, +:hangup+ when the line
    # dropped.
    def send_files(session, files, wait: WAIT, telnet: true)
      Sender.new(session, telnet: telnet).run(files, wait: wait)
    end

    # Returns the CRC-16/XMODEM (polynomial 0x1021) of the String +bytes+,
    # continuing from +crc+.
    def crc16(bytes, crc = 0)
      bytes.each_byte do |b|
        crc ^= b << 8
        8.times { crc = crc.anybits?(CRC16_TOP) ? ((crc << 1) ^ CRC16_POLY) & CRC16_MASK : (crc << 1) & CRC16_MASK }
      end
      crc
    end

    # Returns a binary copy of +bytes+ with every C0 and C1 control byte
    # (0x00-0x1f, 0x80-0x9f) replaced by ZDLE and the byte XOR 0x40.
    def escape(bytes)
      out = +''.b
      bytes.each_byte do |b|
        case b
        when ESCAPED_C0, ESCAPED_C1 then out << ZDLE << (b ^ ZDLE_XOR)
        else out << b
        end
      end
      out
    end
  end
end

require_relative 'zmodem/frames'
require_relative 'zmodem/input'
require_relative 'zmodem/output'
require_relative 'zmodem/stream'
require_relative 'zmodem/sender'
