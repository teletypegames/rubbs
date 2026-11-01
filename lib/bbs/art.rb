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
    Hotspot = Struct.new(:name, :col, :row, :width, :height)

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

    # The Color of +value+, a palette entry: a C64 colour name, a 256-colour
    # index or <tt>#rrggbb</tt>. Raises ArgumentError for anything else.
    def self.color(value)
      case value
      when Integer
        raise ArgumentError, "a 256-colour index is 0-255, not #{value}" unless value.between?(0, 255)

        Color.new(Petscii::Canvas.nearest(rgb256(value)), value)
      when /\A#\h{6}\z/
        rgb = value[1..].scan(/../).map(&:hex)
        Color.new(Petscii::Canvas.nearest(rgb), ansi256(rgb))
      else
        c64 = Petscii::Canvas.color(value)
        Color.new(c64, ansi256(Petscii::Canvas::RGB[c64]))
      end
    end

    # The xterm 256-colour index nearest to +rgb+, [red, green, blue], from
    # the colour cube and the grey ramp (16-255: the first sixteen differ
    # from terminal to terminal).
    def self.ansi256(rgb) = (16..255).min_by { |i| rgb256(i).zip(rgb).sum { |a, b| (a - b)**2 } }

    # The [red, green, blue] of xterm 256-colour index +index+ (the first
    # sixteen as xterm's defaults).
    def self.rgb256(index)
      return SYSTEM_RGB[index] if index < 16
      return [8 + ((index - 232) * 10)] * 3 if index >= 232

      i = index - 16
      [CUBE[i / 36], CUBE[(i / 6) % 6], CUBE[i % 6]]
    end

    # The default colours of xterm's first sixteen indexes.
    SYSTEM_RGB = [[0, 0, 0], [205, 0, 0], [0, 205, 0], [205, 205, 0], [0, 0, 238], [205, 0, 205], [0, 205, 205],
                  [229, 229, 229], [127, 127, 127], [255, 0, 0], [0, 255, 0], [255, 255, 0], [92, 92, 255],
                  [255, 0, 255], [0, 255, 255], [255, 255, 255]].freeze

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

    # The art as lines of 256-colour ANSI: each line starts with its own
    # colours and ends with a reset, so a line can be written anywhere.
    def ansi_lines
      @grid.map do |row|
        line = +''
        sgr  = nil
        row.each do |cell|
          s = Art.sgr(cell)
          line << s if s != sgr
          sgr = s
          line << cell.char
        end
        line << Ansi::RESET
      end
    end

    # The #ansi_lines joined with CR LF, for writing at the start of a line.
    def ansi = ansi_lines.join(Ansi::CRLF)

    # The SGR sequence of +cell+: a reset, then its 256-colour foreground
    # and background and reverse video.
    def self.sgr(cell)
      parts = ['0']
      parts << "38;5;#{cell.fg.ansi}" if cell.fg
      parts << "48;5;#{cell.bg.ansi}" if cell.bg
      parts << '7' if cell.rvs
      "\e[#{parts.join(';')}m"
    end

    # Draws the art on +frame+, a BBS::FrameBuffer, with its top left at
    # +x+, +y+ (1-based), cut to +width+ × +height+ cells (default the
    # whole art) and to the buffer. A cell with no colours gets no style.
    #
    # Returns +frame+.
    def draw(frame, x: 1, y: 1, width: @cols, height: @rows)
      [height, @rows].min.times do |r|
        [width, @cols].min.times do |c|
          cell = @grid[r][c]
          plain = cell.fg.nil? && cell.bg.nil? && !cell.rvs
          frame.move(x + c, y + r)
          frame.write(cell.char, sgr: plain ? nil : Art.sgr(cell))
        end
      end
      frame
    end

    # Draws the art on +canvas+, a BBS::Petscii::Canvas, with its top left
    # at +row+, +col+ (0-based); cells off the screen are cut. A visible
    # cell with no colour is light grey, the C64's text colour. Raises
    # ArgumentError for a cp437 art.
    #
    # Returns +canvas+.
    def draw_canvas(canvas, row: 0, col: 0)
      raise ArgumentError, "#{@path}: a #{@charset} art does not go on a C64 canvas" unless petscii?

      @grid.each_with_index do |cells, r|
        cells.each_with_index do |cell, c|
          code, reversed = Petscii::Canvas.code(cell.char)
          color = cell.fg ? cell.fg.c64 : Petscii::Canvas::LIGHT_GREY
          canvas.put(row + r, col + c, code, color, rvs: cell.rvs ^ reversed)
        end
      end
      canvas
    end

    # A new BBS::Petscii::Canvas with the art drawn at its top left.
    def canvas = draw_canvas(Petscii::Canvas.new)

    # The raw PETSCII of the whole screen with the art on it (the #canvas's
    # +frame+), a binary String to send with <tt>session.write_raw</tt>.
    def petscii = canvas.frame

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
    # adds its palette and hotspots (moved by its +at+) and records +name+ among #stacked.
    def overlay(layer, name)
      @grid = @grid.map(&:dup)
      lc, lr = layer.at
      layer.grid.each_with_index do |cells, r|
        cells.each_with_index do |cell, c|
          next if cell.transparent?
          next unless (lr + r).between?(0, @rows - 1) && (lc + c).between?(0, @cols - 1)

          @grid[lr + r][lc + c] = cell
        end
      end
      @palette = @palette.merge(layer.palette)
      moved = layer.hotspots.transform_values { |h| Hotspot.new(h.name, h.col + lc, h.row + lr, h.width, h.height) }
      @hotspots = @hotspots.merge(moved)
      @stacked += [name]
    end

    private

    def fail!(message) = raise(Error, "#{@path}: #{message}")

    def read_size(data, base)
      size = data['size'] || (base && [base.cols, base.rows])
      unless size.is_a?(Array) && size.size == 2 && size.all? { |n| n.is_a?(Integer) && n.positive? }
        fail!("size must be [columns, rows], not #{size.inspect}")
      end
      size
    end

    def read_at(data)
      at = data['at'] || [0, 0]
      fail!("at must be [col, row], not #{at.inspect}") unless at.is_a?(Array) && at.size == 2 && at.all?(Integer)
      at
    end

    def read_charset(data, base)
      charset = (data['charset'] || base&.charset).to_s
      fail!("charset must be one of #{CHARSETS.join(', ')}, not #{charset.inspect}") unless CHARSETS.include?(charset)
      fail!("a layer of a #{base.charset} art cannot be #{charset}") if base && base.charset != charset
      charset
    end

    def read_palette(palette)
      fail!('palette must be a mapping of letter => colour') unless palette.is_a?(Hash)

      palette.each_with_object({}) do |(letter, value), out|
        letter = letter.to_s
        if letter.length != 1 || NO_COLOR.include?(letter)
          fail!("palette letter #{letter.inspect} must be one character, not '.' or a space")
        end
        out[letter] = Art.color(value)
      rescue ArgumentError => e
        fail!("palette #{letter}: #{e.message}")
      end
    end

    # The grids, checked against each other and the size, as rows of Cell.
    def read_grid(data)
      chars = lines(data, 'chars', required: true)
      colors = lines(data, 'colors', required: true)
      reverse = lines(data, 'reverse')
      background = lines(data, 'background')
      fail!('background is for cp437 art; a C64 has one background (use reverse)') if background && petscii?

      Array.new(@rows) do |r|
        Array.new(@cols) do |c|
          Cell.new(glyph(chars[r][c], r, c), paint(colors[r][c], 'colors', r, c),
                   background && paint(background[r][c], 'background', r, c),
                   reversed?(reverse && reverse[r][c], r, c))
        end
      end
    end

    # The rows of grid +key+, each exactly #cols wide, #rows of them.
    def lines(data, key, required: false)
      text = data[key]
      return fail!("#{key} is missing") if text.nil? && required
      return nil if text.nil?

      fail!("#{key} must be a block of text (#{key}: |)") unless text.is_a?(String)
      rows = text.split("\n", -1)
      rows.pop if rows.last == ''
      fail!("#{key} has #{rows.size} rows, the art #{@rows}") unless rows.size == @rows
      rows.each_with_index do |row, r|
        fail!("#{key} row #{r} is #{row.length} wide, the art #{@cols}#{INDENT_HINT}") unless row.length == @cols
      end
      rows
    end

    def glyph(ch, row, col)
      ok = petscii? ? Petscii::Canvas.glyph?(ch) : cp437?(ch)
      fail!("chars row #{row} col #{col}: #{ch.inspect} is not in #{@charset}") unless ok
      ch
    end

    def cp437?(ch)
      return true if CP437_PICTURES.include?(ch)
      return false if ch.ord < 0x20

      ch.encode(Encoding::IBM437)
      true
    rescue EncodingError
      false
    end

    def paint(letter, key, row, col)
      return nil if NO_COLOR.include?(letter)

      @palette.fetch(letter) do
        fail!("#{key} row #{row} col #{col}: #{letter.inspect} is not in the palette (#{@palette.keys.join})")
      end
    end

    def reversed?(letter, row, col)
      return false if letter.nil? || NO_COLOR.include?(letter)
      return true if letter == REVERSED

      fail!("reverse row #{row} col #{col}: #{letter.inspect} is neither #{REVERSED} nor '.'")
    end

    def read_hotspots(spots)
      fail!('hotspots must be a mapping of name => [col, row]') unless spots.is_a?(Hash)

      spots.to_h do |name, place|
        unless place.is_a?(Array) && [2, 4].include?(place.size) && place.all?(Integer)
          fail!("hotspot #{name} must be [col, row] or [col, row, width, height], not #{place.inspect}")
        end
        col, row, width, height = place
        spot = Hotspot.new(name.to_sym, col, row, width || 1, height || 1)
        unless col >= 0 && row >= 0 && spot.width.positive? && spot.height.positive? &&
               col + spot.width <= @cols && row + spot.height <= @rows
          fail!("hotspot #{name} #{place.inspect} is not inside the #{@cols}×#{@rows} art")
        end
        [spot.name, spot]
      end
    end
  end
end
