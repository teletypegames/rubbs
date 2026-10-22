# frozen_string_literal: true

require_relative 'frame_buffer'

module BBS
  # Markdown → ANSI line array renderer.
  #
  #   BBS::Markdown.to_lines(text, width:, theme:)
  #
  # Returns an array of strings (one per terminal line) with embedded ANSI SGR
  # codes — suitable for BBS::Widgets::ScrollView. Each inline span ends with
  # the theme :text SGR so that trailing text keeps the right background.
  module Markdown
    module_function

    def to_lines(text, width:, theme:)
      text = FrameBuffer.text(text)
      styles = {
        base:   theme[:text],
        h1:     theme[:text_bright],
        h2:     theme[:accent],
        h3:     theme[:label],
        bold:   theme[:text_bright],
        italic: theme[:text_dim],
        code:   theme[:label],
        link:   theme[:accent],
        quote:  theme[:text_dim],
        bullet: theme[:accent],
        rule:   theme[:label],
      }
      result    = []
      paragraph = []
      in_code   = false
      base      = styles[:base]

      flush_paragraph = lambda do
        next if paragraph.empty?
        joined = paragraph.join(' ').gsub(/\s+/, ' ').strip
        FrameBuffer.wrap_ansi(inline(joined, styles, base), width).each { |l| result << l }
        paragraph.clear
      end

      lines = text.to_s.split(/\r?\n/)
      i     = 0
      while i < lines.size
        line     = lines[i]
        consumed = 1

        if line.lstrip.start_with?('```')
          flush_paragraph.call
          in_code = !in_code

        elsif in_code
          flush_paragraph.call
          clipped = FrameBuffer.clip_ansi(line, width)
          result << "#{styles[:code]}#{clipped}#{base}"

        elsif line.strip.empty?
          flush_paragraph.call
          result << ''

        elsif (m = line.match(/\A([#]{1,6})\s+(.+?)\s*#*\s*\z/))
          level   = m[1].length
          heading = m[2].strip
          flush_paragraph.call
          style = level == 1 ? styles[:h1] : (level == 2 ? styles[:h2] : styles[:h3])
          FrameBuffer.wrap_ansi(inline(heading, styles, base), width).each do |l|
            result << "#{style}#{l}#{base}"
          end

        elsif line.include?('|') && (i + 1) < lines.size && separator_row?(lines[i + 1])
          flush_paragraph.call
          header = split_row(line)
          aligns = parse_aligns(lines[i + 1], header.size)
          rows   = []
          j      = i + 2
          while j < lines.size && lines[j].include?('|') &&
                !lines[j].strip.empty? && !lines[j].lstrip.start_with?('```')
            rows << split_row(lines[j])
            j += 1
          end
          render_table(header, aligns, rows, width, styles, base).each { |l| result << l }
          consumed = j - i

        elsif line.match?(/\A\s*([-*_])\1{2,}\s*\z/)
          flush_paragraph.call
          result << "#{styles[:rule]}#{'─' * width}#{base}"

        elsif (m = line.match(/\A\s*>\s?(.*)/))
          content = m[1]
          flush_paragraph.call
          inner_w = [width - 2, 1].max
          FrameBuffer.wrap_ansi(inline(content, styles, base), inner_w).each do |l|
            result << "#{styles[:quote]}│ #{base}#{l}"
          end

        elsif (m = line.match(/\A(\s*)[-*+]\s+(.+)/))
          indent = m[1].length
          body, consumed = item_body(m[2], lines, i)
          flush_paragraph.call
          prefix_w = indent + 2
          inner_w  = [width - prefix_w, 1].max
          wrapped  = FrameBuffer.wrap_ansi(inline(body, styles, base), inner_w)
          wrapped.each_with_index do |l, k|
            pad = ' ' * indent
            result << if k.zero?
                        "#{pad}#{styles[:bullet]}•#{base} #{l}"
                      else
                        "#{' ' * prefix_w}#{l}"
                      end
          end

        elsif (m = line.match(/\A(\s*)(\d+)\.\s+(.+)/))
          indent = m[1].length
          num    = m[2]
          body, consumed = item_body(m[3], lines, i)
          flush_paragraph.call
          prefix  = "#{' ' * indent}#{num}. "
          inner_w = [width - prefix.length, 1].max
          wrapped = FrameBuffer.wrap_ansi(inline(body, styles, base), inner_w)
          wrapped.each_with_index do |l, k|
            result << if k.zero?
                        "#{' ' * indent}#{styles[:bullet]}#{num}.#{base} #{l}"
                      else
                        "#{' ' * prefix.length}#{l}"
                      end
          end

        else
          paragraph << line.strip
        end

        i += consumed
      end

      flush_paragraph.call
      result
    end

    # A list item's text with its indented continuation lines, and how many
    # source lines it took.
    def item_body(first, lines, index)
      body = [first.strip]
      j    = index + 1
      while j < lines.size && lines[j].match?(/\A\s+\S/) && !lines[j].match?(/\A\s*([-*+]|\d+\.)\s+/)
        body << lines[j].strip
        j += 1
      end
      [body.join(' '), j - index]
    end

    def inline(text, styles, base_sgr)
      s = text.to_s
      s = s.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { "#{styles[:link]}#{::Regexp.last_match(1)}#{base_sgr}" }
      s = s.gsub(/`([^`]+)`/) { "#{styles[:code]}#{::Regexp.last_match(1)}#{base_sgr}" }
      s = s.gsub(/\*\*([^*]+)\*\*/) { "#{styles[:bold]}#{::Regexp.last_match(1)}#{base_sgr}" }
      s = s.gsub(/(?<![A-Za-z0-9*])\*([^*\s][^*]*?[^*\s]|\S)\*(?![A-Za-z0-9*])/) do
        "#{styles[:italic]}#{::Regexp.last_match(1)}#{base_sgr}"
      end
      s = s.gsub(/(?<![A-Za-z0-9_])_([^_\s][^_]*?[^_\s]|\S)_(?![A-Za-z0-9_])/) do
        "#{styles[:italic]}#{::Regexp.last_match(1)}#{base_sgr}"
      end
      s.gsub(/\\([\\`*_{}\[\]()#+\-.!>])/) { ::Regexp.last_match(1) }
    end

    # ── GFM tables ───────────────────────────────────────────────────────────

    # Split a `| a | b |` table row into trimmed cell strings, tolerating
    # missing leading/trailing pipes.
    def split_row(line)
      s = line.strip
      s = s[1..]  if s.start_with?('|')
      s = s[0..-2] if s.end_with?('|')
      s.split('|').map(&:strip)
    end

    # True when a line is a table delimiter row, e.g. `|---|:--:|---:|`.
    def separator_row?(line)
      return false unless line.include?('-')
      cells = split_row(line)
      !cells.empty? && cells.all? { |c| c.match?(/\A:?-{1,}:?\z/) }
    end

    # Per-column alignment (:left / :center / :right) derived from the
    # delimiter row, padded/truncated to `ncols`.
    def parse_aligns(sep_line, ncols)
      cells = split_row(sep_line)
      aligns = cells.map do |c|
        left  = c.start_with?(':')
        right = c.end_with?(':')
        if left && right then :center
        elsif right       then :right
        else                   :left
        end
      end
      aligns << :left while aligns.size < ncols
      aligns[0, ncols]
    end

    # Render a parsed table as box-drawn ANSI lines that fit within `width`.
    def render_table(header, aligns, rows, width, styles, base)
      ncols = header.size
      return [] if ncols.zero?

      all_rows = [header] + rows
      # Normalise ragged rows to ncols and pre-render inline styling per cell.
      rendered = all_rows.map do |row|
        Array.new(ncols) { |c| inline(row[c].to_s, styles, base) }
      end

      widths = Array.new(ncols, 1)
      rendered.each do |row|
        ncols.times do |c|
          w = FrameBuffer.visible_width(row[c])
          widths[c] = w if w > widths[c]
        end
      end

      # Shrink columns proportionally if the table overflows the pane.
      # Frame overhead: one space of padding each side of every cell plus the
      # vertical borders (ncols + 1).
      overhead = (ncols * 2) + (ncols + 1)
      avail    = [width - overhead, ncols].max
      while widths.sum > avail
        widest = widths.each_index.max_by { |c| widths[c] }
        break if widths[widest] <= 1
        widths[widest] -= 1
      end

      bar       = "#{styles[:rule]}│#{base}"
      border    = lambda do |left, mid, right|
        segs = widths.map { |w| '─' * (w + 2) }
        "#{styles[:rule]}#{left}#{segs.join(mid)}#{right}#{base}"
      end
      data_line = lambda do |row, header_row|
        cells = ncols.times.map do |c|
          " #{fit_cell(row[c], widths[c], aligns[c], styles, base, header_row)} "
        end
        bar + cells.join(bar) + bar
      end

      out = []
      out << border.call('┌', '┬', '┐')
      out << data_line.call(rendered[0], true)
      out << border.call('├', '┼', '┤')
      rendered[1..].each { |row| out << data_line.call(row, false) }
      out << border.call('└', '┴', '┘')
      out
    end

    # Clip-or-pad a pre-styled cell to the column width, honouring alignment.
    def fit_cell(styled, w, align, styles, base, header_row)
      content = header_row ? "#{styles[:bold]}#{styled}#{base}" : styled
      vis     = FrameBuffer.visible_width(styled)
      return "#{FrameBuffer.clip_ansi(content, w)}#{base}" if vis > w

      pad = w - vis
      case align
      when :right  then "#{' ' * pad}#{content}"
      when :center then "#{' ' * (pad / 2)}#{content}#{' ' * (pad - pad / 2)}"
      else              "#{content}#{' ' * pad}"
      end
    end
  end
end
