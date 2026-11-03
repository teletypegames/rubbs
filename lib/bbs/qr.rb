# frozen_string_literal: true

require 'rqrcode_core'

module BBS
  # QR codes drawn in text, for a phone to read off the caller's screen: an
  # address to open in a browser, a link to read on.
  #
  # The code is encoded by the +rqrcode_core+ gem and drawn white on black
  # with block characters, two modules to a cell, so its modules come out
  # square on either kind of screen:
  #
  # [#ansi]    for a modern terminal, whose cells are twice as tall as they
  #            are wide: half blocks (<tt>▀ ▄ █</tt>), two modules on top of
  #            each other in a cell
  # [#petscii] for a Commodore 64, whose cells are square: quadrant blocks,
  #            two by two modules in a cell; the quadrants the C64 has not
  #            got are the reverse of those it has
  #
  # Both return the lines of the code with their colours as ANSI SGR, which
  # a PETSCII session turns into the C64's colours and RVS codes, so a line
  # goes out with +puts+ or into a window body as it is:
  #
  #   BBS::QR.petscii(item.link).each { |line| screen.puts(" #{line}") }
  #
  #   BBS::Windows::Info.open(app, title: ' Scan me ', body: BBS::QR.ansi(url, width: 60, height: 20))
  #
  # The code takes the smallest version that holds the text and fits in the
  # room given; a text that does not fit raises TooLong.
  module QR
    # Raised when the text does not fit in a QR code of the size allowed.
    class TooLong < ArgumentError; end

    # The light modules around the code, on each side. The standard asks for
    # four; two read well off a screen and leave more room for the code.
    QUIET = 2
    # The error correction level: +:l+, the lowest, gives the fewest and so
    # the biggest modules, and a screen does not get dirty.
    LEVEL = :l
    # The modules of a version 1 code on a side; each version adds VERSION_STEP.
    VERSION_ONE = 21
    # The modules a version adds to a side.
    VERSION_STEP = 4
    # The highest QR code version.
    MAX_VERSION = 40
    # The pen of a code: white light modules on black dark ones.
    PEN = "\e[97;40m"
    # A half-block cell of #ansi by its modules, <tt>[top dark?, bottom dark?]</tt>.
    HALF_BLOCKS = {
      [false, false] => '█', [false, true] => '▀', [true, false] => '▄', [true, true] => ' '
    }.freeze
    # The quadrant cells the C64 has a character for, by the bits of their
    # light modules: 8 upper left, 4 upper right, 2 lower left, 1 lower
    # right. Every other cell is the reverse of the one with the opposite
    # bits.
    QUADRANTS = { 0 => ' ', 8 => '▘', 4 => '▝', 2 => '▖', 1 => '▗', 9 => '▚', 10 => '▌', 3 => '▄' }.freeze
    # All the bits of a quadrant cell.
    FULL = 15
    # Reverse video turned off and on again between two reversed cells,
    # dropped so a run of them is one.
    REVERSE_AGAIN = "#{Ansi::REVERSE_OFF}#{Ansi::REVERSE}".freeze

    # The modules of the QR code of +text+, row by row, +true+ for a dark
    # one, without the quiet zone.
    #
    # [level]       the error correction level: +:l+, +:m+, +:q+ or +:h+
    # [max_version] the highest version (size) allowed, 1-40
    #
    # Raises TooLong when +text+ does not fit in +max_version+.
    def self.modules(text, level: LEVEL, max_version: MAX_VERSION)
      raise TooLong, 'no room for a QR code' if max_version < 1

      RQRCodeCore::QRCode.new(text.to_s, level: level, max_size: [max_version, MAX_VERSION].min).modules
    rescue RQRCodeCore::QRCodeRunTimeError => e
      raise TooLong, e.message
    end

    # The QR code of +text+ for a modern terminal: lines of half blocks,
    # each two rows of modules, the quiet zone included.
    #
    # [width]  the most columns the code may take
    # [height] the most lines the code may take
    # [quiet]  the light modules around the code on each side
    # [level]  the error correction level (see #modules)
    #
    # Returns an Array of Strings with ANSI colours. Raises TooLong when
    # +text+ does not fit in +width+ × +height+.
    def self.ansi(text, width: 80, height: 24, quiet: QUIET, level: LEVEL)
      grid = framed(text, [width, height * 2].min, quiet, level)
      grid.each_slice(2).map do |top, bottom|
        PEN + top.zip(bottom).map { |pair| HALF_BLOCKS.fetch(pair) }.join + Ansi::RESET
      end
    end

    # The QR code of +text+ for a Commodore 64: lines of quadrant blocks,
    # each two rows of modules two columns to a cell, the quiet zone
    # included. The defaults leave the C64's last column free (a full row
    # would wrap) and five rows for a title and a prompt.
    #
    # [cols]  the most columns the code may take
    # [rows]  the most lines the code may take
    # [quiet] the light modules around the code on each side
    # [level] the error correction level (see #modules)
    #
    # Returns an Array of Strings with ANSI colours and reverse video.
    # Raises TooLong when +text+ does not fit in +cols+ × +rows+.
    def self.petscii(text, cols: Petscii::COLS - 1, rows: Petscii::ROWS - 5, quiet: QUIET, level: LEVEL)
      grid = framed(text, [cols, rows].min * 2, quiet, level)
      grid.each_slice(2).map do |top, bottom|
        cells = top.each_slice(2).zip(bottom.each_slice(2)).map { |(a, b), (c, d)| quadrant(a, b, c, d) }
        PEN + cells.join.gsub(REVERSE_AGAIN, '') + Ansi::RESET
      end
    end

    # The modules of +text+ in a quiet zone of +quiet+ light modules, an
    # even number of them on a side, at most +room+.
    def self.framed(text, room, quiet, level)
      core  = modules(text, level: level, max_version: ((room - (2 * quiet) - VERSION_ONE - 1) / VERSION_STEP) + 1)
      side  = core.size + (2 * quiet) + 1
      blank = Array.new(side, false)
      rows  = core.map { |row| [*Array.new(quiet, false), *row, *Array.new(quiet + 1, false)] }
      [*Array.new(quiet) { blank }, *rows, *Array.new(quiet + 1) { blank }]
    end
    private_class_method :framed

    # The cell of four modules (+true+ for dark): upper left +a+, upper
    # right +b+, lower left +c+, lower right +d+.
    def self.quadrant(a, b, c, d)
      light = [a, b, c, d].each_with_index.sum { |dark, i| dark ? 0 : 8 >> i }
      QUADRANTS.fetch(light) { "#{Ansi::REVERSE}#{QUADRANTS.fetch(FULL ^ light)}#{Ansi::REVERSE_OFF}" }
    end
    private_class_method :quadrant
  end
end
