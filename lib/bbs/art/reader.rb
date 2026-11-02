# frozen_string_literal: true

module BBS
  class Art
    # How an Art reads its file: each key of the YAML checked, a mistake
    # raised as an Art::Error that names the file and the cell.
    module Reader
      private

      def fail!(message) = raise(Error, "#{@path}: #{message}")

      def read_size(data, base)
        size = data['size'] || (base && [base.cols, base.rows])
        fail!("size must be [columns, rows], not #{size.inspect}") unless pair?(size) && size.all?(&:positive?)
        size
      end

      def read_at(data)
        at = data['at'] || [0, 0]
        fail!("at must be [col, row], not #{at.inspect}") unless pair?(at)
        at
      end

      def pair?(value) = value.is_a?(Array) && value.size == 2 && value.all?(Integer)

      def read_charset(data, base)
        charset = (data['charset'] || base&.charset).to_s
        fail!("charset must be one of #{CHARSETS.join(', ')}, not #{charset.inspect}") unless CHARSETS.include?(charset)
        fail!("a layer of a #{base.charset} art cannot be #{charset}") if base && base.charset != charset
        charset
      end

      def read_palette(palette)
        fail!('palette must be a mapping of letter => colour') unless palette.is_a?(Hash)

        palette.to_h { |letter, value| palette_entry(letter.to_s, value) }
      end

      def palette_entry(letter, value)
        if letter.length != 1 || NO_COLOR.include?(letter)
          fail!("palette letter #{letter.inspect} must be one character, not '.' or a space")
        end
        [letter, Art.color(value)]
      rescue ArgumentError => e
        fail!("palette #{letter}: #{e.message}")
      end

      # The grids, checked against each other and the size, as rows of Cell.
      def read_grid(data)
        grids = { chars: lines(data, 'chars', required: true), colors: lines(data, 'colors', required: true),
                  reverse: lines(data, 'reverse'), background: lines(data, 'background') }
        fail!('background is for cp437 art; a C64 has one background (use reverse)') if grids[:background] && petscii?

        Array.new(@rows) { |r| Array.new(@cols) { |c| read_cell(grids, r, c) } }
      end

      def read_cell(grids, row, col)
        at = ->(grid) { grid && grid[row][col] }
        Cell.new(glyph(at[grids[:chars]], row, col), paint(at[grids[:colors]], 'colors', row, col),
                 grids[:background] && paint(at[grids[:background]], 'background', row, col),
                 reversed?(at[grids[:reverse]], row, col))
      end

      # The rows of grid +key+, each exactly #cols wide, #rows of them;
      # +nil+ for a grid the file leaves out.
      def lines(data, key, required: false)
        text = data[key]
        fail!("#{key} is missing") if text.nil? && required
        return nil if text.nil?

        fail!("#{key} must be a block of text (#{key}: |)") unless text.is_a?(String)
        rows = text.split("\n", -1)
        rows.pop if rows.last == ''
        check_rows(key, rows)
      end

      def check_rows(key, rows)
        fail!("#{key} has #{rows.size} rows, the art #{@rows}") unless rows.size == @rows
        rows.each_with_index do |row, r|
          fail!("#{key} row #{r} is #{row.length} wide, the art #{@cols}#{INDENT_HINT}") unless row.length == @cols
        end
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
          spot = hotspot_at(name, place)
          [spot.name, spot]
        end
      end

      def hotspot_at(name, place)
        unless place.is_a?(Array) && [2, 4].include?(place.size) && place.all?(Integer)
          fail!("hotspot #{name} must be [col, row] or [col, row, width, height], not #{place.inspect}")
        end
        col, row, width, height = place
        spot = Hotspot.new(name.to_sym, col, row, width || 1, height || 1)
        fail!("hotspot #{name} #{place.inspect} is not inside the #{@cols}×#{@rows} art") unless spot.inside?(@cols, @rows)
        spot
      end
    end

    include Reader
  end
end
