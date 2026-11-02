# frozen_string_literal: true

require 'yaml'

module BBS
  # A drawing kept as readable, diffable text: a YAML file of a character
  # grid and a colour grid, for either face of a board. The modern face
  # draws it in 256-colour ANSI (#ansi_lines, #draw on a BBS::FrameBuffer,
  # BBS::Widgets::Scene), the C64 face as raw PETSCII on a
  # BBS::Petscii::Canvas (#draw_canvas, #petscii).
  #
  # The format (<tt>art/house.yml</tt>):
  #
  #   size: [40, 6]           # columns, rows
  #   charset: petscii-upper  # or cp437
  #   palette:                # letter => colour
  #     y: yellow             #   a C64 colour name (BBS::Petscii::Canvas::COLOR_NAMES)
  #     o: 208                #   an xterm 256-colour index
  #     s: '#3050a0'          #   or #rrggbb
  #   chars: |2               # the picture, a line a row, every row size[0] wide
  #     ...
  #   colors: |2              # a palette letter a cell; '.' or space: no colour
  #     ...
  #   reverse: |2             # optional: 'R' reverses the cell
  #     ...
  #   background: |2          # optional, cp437 only: a palette letter a cell
  #     ...
  #   hotspots:               # optional: cells the board fills from its data
  #     window_1: [12, 3]     #   [col, row], 0-based
  #     sign: [2, 1, 10, 1]   #   [col, row, width, height]
  #   layers: [snow, pumpkin] # optional: layer files beside this one
  #
  # [grids]      +chars+, +colors+, +reverse+ and +background+ are YAML
  #              literal blocks, every row exactly as wide as the art (the
  #              trailing spaces too), as many rows as it is high. Write them
  #              <tt>|2</tt>: without the indentation indicator YAML takes
  #              the indentation from the first row, and a row starting
  #              with spaces breaks the block.
  # [chars]      In +petscii-upper+ every character must be one the
  #              uppercase/graphics set shows (BBS::Petscii::Canvas.glyph?):
  #              letters, digits, signs and the graphics of
  #              Canvas::GLYPHS and Canvas::GLYPHS_REVERSED. In +cp437+ every
  #              character must be in code page 437.
  # [reverse]    A reversed cell swaps its colours: a reversed space in
  #              yellow is a yellow block. The reversed glyphs of the Canvas
  #              (<tt>█ ▀ ▐ ◢ ◣</tt>) are drawn as they look; reversing them
  #              inverts them again.
  # [background] The colour behind a cp437 cell, the second colour of a half
  #              block. A C64 has one background for the whole screen, so a
  #              petscii-upper art draws with reversed cells instead.
  # [layers]     A layer is a file of the same format, <tt><name>.yml</tt>
  #              in the same folder. +size+ defaults to the art's, +at+
  #              (<tt>[col, row]</tt>) places it, +charset+ must match, its
  #              palette adds to (and overrides) the art's, its hotspots add
  #              to the art's. A layer cell that is a plain space (not
  #              reversed, no background) is transparent. #with stacks the
  #              layers chosen, in the order given.
  #
  # Every mistake raises Art::Error naming the file, the grid, the row and
  # the column.
  #
  #   art = BBS::Art.load('art/house.yml').with(*BBS::Season.now.layers)
  #   session.write(art.ansi)                     # modern face
  #   session.write_raw(art.petscii)              # C64 face: a whole frame
  #   art.hotspot(:window_1)                      # => #<struct col=12, row=3 …>
  class Art
    # A mistake in an art file: the message names the file and the cell.
    class Error < StandardError; end

    # The character sets an art is drawn in.
    CHARSETS = %w[petscii-upper cp437].freeze
    # The letters of the colour grids that mean no colour.
    NO_COLOR = ['.', ' '].freeze
    # The letter of the reverse grid that reverses a cell.
    REVERSED = 'R'
    # The pictures code page 437 shows for its control codes 1-31 and 127,
    # which Ruby's IBM437 encoding keeps as controls.
    CP437_PICTURES = '☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼⌂'
    # The levels of the 6×6×6 colour cube of xterm (indexes 16-231).
    CUBE = [0, 95, 135, 175, 215, 255].freeze

    # A colour of the palette in both forms: +c64+ the PETSCII colour code,
    # +ansi+ the xterm 256-colour index.
    Color = Struct.new(:c64, :ansi)

    # One cell: its +char+ (a one-character String), its foreground +fg+
    # and background +bg+ (Color or +nil+) and whether it is reversed
    # (+rvs+).
    Cell = Struct.new(:char, :fg, :bg, :rvs) do
      # Whether a layer leaves the cell under it showing: a plain space.
      def transparent? = char == ' ' && !rvs && bg.nil?
    end

    # A named place on the art the board fills from its data: its +name+
    # (a Symbol), its top-left +col+ and +row+ (0-based) and its +width+
    # and +height+ in cells.
    Hotspot = Struct.new(:name, :col, :row, :width, :height) do
      # The same hotspot moved by +cols+ and +rows+.
      def moved(cols, rows) = Hotspot.new(name, col + cols, row + rows, width, height)

      # Whether it is a real area inside an art of +cols+ × +rows+.
      def inside?(cols, rows)
        col >= 0 && row >= 0 && width.positive? && height.positive? && col + width <= cols && row + height <= rows
      end
    end

    # The file the art came from ('(string)' for ::parse).
    attr_reader :path
    # The width and height in cells.
    attr_reader :cols, :rows
    # The character set: one of CHARSETS.
    attr_reader :charset
    # The palette: a Hash of letter => Color.
    attr_reader :palette
    # The hotspots: a Hash of Symbol name => Hotspot.
    attr_reader :hotspots
    # The names of the layers the file lists (Strings), stacked or not.
    attr_reader :layers
    # The names of the layers stacked on this one by #with.
    attr_reader :stacked

    # Loads the art at +path+, a YAML file of the format above; with
    # +layers+ (an Array of names, or +:all+) the layers stacked on it (see
    # #with). Raises Art::Error for a mistake in the art or a layer,
    # SystemCallError when a file cannot be read.
    def self.load(path, layers: nil)
      art = parse(File.read(path), path: path)
      return art if layers.nil?

      layers == :all ? art.with(*art.layers) : art.with(*layers)
    end

    # Parses +text+, the YAML of an art; +path+ names it in the errors and
    # its folder is where the layers are looked for. Raises Art::Error.
    def self.parse(text, path: '(string)')
      data = YAML.safe_load(text)
      raise Error, "#{path}: not a YAML mapping" unless data.is_a?(Hash)

      new(data, path: path)
    rescue Psych::SyntaxError => e
      raise Error, "#{path}: #{e.message}#{INDENT_HINT}"
    end

    # Added to the errors YAML's indentation can cause.
    INDENT_HINT = ' (a grid whose first row starts with a space needs the indentation indicator: chars: |2)'

    # Builds the art from +data+, the Hash of a parsed file (String keys),
    # read from +path+. +base+ is the art a layer goes on: it gives the
    # size, the charset and the palette a layer leaves out. Raises
    # Art::Error.
    def initialize(data, path: '(string)', base: nil)
      @path     = path
      @stacked  = []
      @cols, @rows = read_size(data, base)
      @at       = base ? read_at(data) : [0, 0]
      @charset  = read_charset(data, base)
      @palette  = (base ? base.palette : {}).merge(read_palette(data['palette'] || {}))
      @grid     = read_grid(data)
      @hotspots = read_hotspots(data['hotspots'] || {})
      @layers   = Array(data['layers']).map(&:to_s)
    end

    # Whether the art is drawn in the C64's uppercase/graphics set.
    def petscii? = @charset == 'petscii-upper'

    # The Cell at +col+, +row+ (0-based), or +nil+ outside the art.
    def cell(col, row)
      return nil unless row.between?(0, @rows - 1) && col.between?(0, @cols - 1)

      @grid[row][col]
    end

    # The Hotspot named +name+ (a Symbol or String). Raises Art::Error for
    # a name the art does not have.
    def hotspot(name)
      @hotspots.fetch(name.to_sym) { raise Error, "#{@path}: no hotspot #{name} (#{@hotspots.keys.join(', ')})" }
    end

    # A new art: this one with the layers +names+ stacked on it, in that
    # order (each a String or Symbol among #layers; +nil+ and names the file
    # does not list are skipped, so <tt>art.with(*BBS::Season.now.layers)</tt>
    # takes only the layers the art has). The layer files are read from the
    # folder of #path. Raises Art::Error for a mistake in a layer,
    # SystemCallError when one cannot be read.
    def with(*names)
      names = names.compact.map(&:to_s).select { |n| @layers.include?(n) }
      names.reduce(self) { |art, name| art.stack(name) }
    end

    protected

    # The rows of cells.
    attr_reader :grid

    # The cell offset of a layer: [col, row].
    attr_reader :at

    # A copy of this art with the layer +name+ stacked on it.
    def stack(name)
      layer_path = File.join(File.dirname(@path), "#{name}.yml")
      text = File.read(layer_path)
      data = YAML.safe_load(text)
      raise Error, "#{layer_path}: not a YAML mapping" unless data.is_a?(Hash)

      layer = Art.new(data, path: layer_path, base: self)
      copy  = dup
      copy.overlay(layer, name)
      copy
    rescue Psych::SyntaxError => e
      raise Error, "#{layer_path}: #{e.message}#{INDENT_HINT}"
    end

    # Puts the cells of +layer+ that are not transparent over this art's,
    # adds its palette and hotspots (moved by its +at+) and records +name+
    # among #stacked.
    def overlay(layer, name)
      lc, lr = layer.at
      @grid = @grid.map(&:dup)
      layer.grid.each_with_index { |cells, r| cover(cells, lr + r, lc) }
      @palette  = @palette.merge(layer.palette)
      @hotspots = @hotspots.merge(layer.hotspots.transform_values { |h| h.moved(lc, lr) })
      @stacked += [name]
    end

    private

    # Puts the visible +cells+ of a layer on row +row+ from column +col+.
    def cover(cells, row, col)
      return unless row.between?(0, @rows - 1)

      cells.each_with_index do |cell, c|
        @grid[row][col + c] = cell unless cell.transparent? || !(col + c).between?(0, @cols - 1)
      end
    end
  end
end

require_relative 'art/colors'
require_relative 'art/reader'
require_relative 'art/drawing'
