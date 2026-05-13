# frozen_string_literal: true

module BBS
  class FrameBuffer
    Cell = Struct.new(:char, :sgr)
    BLANK = Cell.new(' ', nil).freeze

    attr_reader :cols, :rows

    def initialize(cols, rows)
      @cols = cols
      @rows = rows
      clear
    end

    def clear
      @cells = Array.new(@rows) { Array.new(@cols) { BLANK } }
      @cx    = 0
      @cy    = 0
    end

    def move(col, row)
      @cx = col.clamp(1, @cols) - 1
      @cy = row.clamp(1, @rows) - 1
    end

    def write(text, sgr: nil)
      text.each_char do |ch|
        break if @cy >= @rows
        @cells[@cy][@cx] = Cell.new(ch, sgr) if @cx < @cols
        @cx += 1
      end
    end

    # Write text that may contain embedded ANSI SGR / cursor sequences.
    # base_sgr is the initial style, overridden by any embedded \e[...m sequences.
    def write_ansi(text, base_sgr: nil)
      cur_sgr = base_sgr
      s       = text.to_s
      i       = 0
      len     = s.length

      while i < len
        ch = s[i]

        if ch == "\e" && i + 1 < len && s[i + 1] == '['
          j = i + 2
          j += 1 while j < len && !s[j].match?(/[A-Za-z]/)

          if j < len
            term  = s[j]
            inner = s[(i + 2)...j]

            case term
            when 'm'
              seq     = s[i..j]
              cur_sgr = (seq == "\e[0m" || seq == "\e[m") ? nil : seq
            when 'H', 'f'
              parts = inner.split(';')
              row   = [parts[0].to_i, 1].max
              col   = [parts[1].to_i, 1].max
              move(col, row)
            when 'J'
              clear if inner == '2'
            end

            i = j + 1
          else
            i += 1
          end
        elsif ch.ord >= 32
          if @cy < @rows && @cx < @cols
            @cells[@cy][@cx] = Cell.new(ch, cur_sgr)
          end
          @cx += 1
          i += 1
        else
          i += 1
        end
      end
    end

    # ── Drawing helpers (1-based coordinates) ────────────────────────────────

    def fill(x:, y:, width:, height:, sgr: nil, char: ' ')
      height.times do |r|
        move(x, y + r)
        write(char * width, sgr: sgr)
      end
    end

    def hline(x:, y:, length:, char: '─', sgr: nil)
      move(x, y)
      write(char * length, sgr: sgr)
    end

    def vline(x:, y:, length:, char: '│', sgr: nil)
      length.times do |r|
        move(x, y + r)
        write(char, sgr: sgr)
      end
    end

    BOX_CHARS = {
      single: { tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│' },
      double: { tl: '╔', tr: '╗', bl: '╚', br: '╝', h: '═', v: '║' },
    }.freeze

    def box(x:, y:, width:, height:, sgr: nil, fill_sgr: nil, style: :single, title: nil, title_sgr: nil, title_indent: 0)
      return if width < 2 || height < 2
      g  = BOX_CHARS[style] || BOX_CHARS[:single]
      iw = width - 2

      move(x, y)
      write(g[:tl], sgr: sgr)
      if title && title.length > 0
        indent  = [title_indent, 0].max
        title_max = [iw - 2 - indent, 0].max
        clipped   = title[0, title_max]
        write(g[:h] * indent, sgr: sgr) if indent > 0
        prefix  = "#{g[:h]} "
        write(prefix, sgr: sgr)
        write(clipped, sgr: title_sgr || sgr)
        rest = iw - indent - prefix.length - clipped.length
        write(g[:h] * [rest, 0].max, sgr: sgr) if rest > 0
      else
        write(g[:h] * iw, sgr: sgr)
      end
      write(g[:tr], sgr: sgr)

      (1...height - 1).each do |r|
        move(x, y + r)
        write(g[:v], sgr: sgr)
        write(' ' * iw, sgr: fill_sgr) if fill_sgr
        move(x + width - 1, y + r)
        write(g[:v], sgr: sgr)
      end

      move(x, y + height - 1)
      write(g[:bl], sgr: sgr)
      write(g[:h] * iw, sgr: sgr)
      write(g[:br], sgr: sgr)
    end

    def shadow(x:, y:, width:, height:, sgr: nil)
      sgr ||= "\e[40m"
      # right edge
      height.times do |r|
        move(x + width, y + 1 + r)
        write('  ', sgr: sgr) if x + width < @cols
      end
      # bottom edge
      move(x + 2, y + height)
      write(' ' * width, sgr: sgr) if y + height <= @rows
    end

    # Compute the minimal ANSI byte stream to transform +from+ into +self+.
    def diff(from)
      out     = +""
      cur_sgr = :_none
      exp_r   = nil
      exp_c   = nil

      @rows.times do |r|
        @cols.times do |c|
          nc = @cells[r][c]
          oc = from.cell_at(r, c)
          next if nc == oc

          unless r == exp_r && c == exp_c
            out << "\e[#{r + 1};#{c + 1}H"
          end

          if nc.sgr != cur_sgr
            out << (nc.sgr || "\e[0m")
            cur_sgr = nc.sgr
          end

          out << nc.char
          exp_r = r
          exp_c = c + 1
        end
      end

      out << "\e[0m" if cur_sgr != :_none && cur_sgr
      out
    end

    protected

    def cell_at(row, col)
      @cells[row][col]
    end
  end
end
