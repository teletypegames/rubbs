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

      text.to_s.split(/\r?\n/).each do |line|
        if line.lstrip.start_with?('```')
          flush_paragraph.call
          in_code = !in_code
          next
        end

        if in_code
          flush_paragraph.call
          clipped = FrameBuffer.clip_ansi(line, width)
          result << "#{styles[:code]}#{clipped}#{base}"
          next
        end

        if line.strip.empty?
          flush_paragraph.call
          result << ''
          next
        end

        if (m = line.match(/\A([#]{1,6})\s+(.+?)\s*#*\s*\z/))
          level   = m[1].length
          heading = m[2].strip
          flush_paragraph.call
          style = level == 1 ? styles[:h1] : (level == 2 ? styles[:h2] : styles[:h3])
          FrameBuffer.wrap_ansi(inline(heading, styles, base), width).each do |l|
            result << "#{style}#{l}#{base}"
          end
          next
        end

        if line.match?(/\A\s*([-*_])\1{2,}\s*\z/)
          flush_paragraph.call
          result << "#{styles[:rule]}#{'─' * width}#{base}"
          next
        end

        if (m = line.match(/\A\s*>\s?(.*)/))
          content = m[1]
          flush_paragraph.call
          inner_w = [width - 2, 1].max
          FrameBuffer.wrap_ansi(inline(content, styles, base), inner_w).each do |l|
            result << "#{styles[:quote]}│ #{base}#{l}"
          end
          next
        end

        if (m = line.match(/\A(\s*)[-*+]\s+(.+)/))
          indent = m[1].length
          body   = m[2]
          flush_paragraph.call
          prefix_w = indent + 2
          inner_w  = [width - prefix_w, 1].max
          wrapped  = FrameBuffer.wrap_ansi(inline(body, styles, base), inner_w)
          wrapped.each_with_index do |l, i|
            pad = ' ' * indent
            result << if i.zero?
                        "#{pad}#{styles[:bullet]}•#{base} #{l}"
                      else
                        "#{' ' * prefix_w}#{l}"
                      end
          end
          next
        end

        if (m = line.match(/\A(\s*)(\d+)\.\s+(.+)/))
          indent = m[1].length
          num    = m[2]
          body   = m[3]
          flush_paragraph.call
          prefix  = "#{' ' * indent}#{num}. "
          inner_w = [width - prefix.length, 1].max
          wrapped = FrameBuffer.wrap_ansi(inline(body, styles, base), inner_w)
          wrapped.each_with_index do |l, i|
            result << if i.zero?
                        "#{' ' * indent}#{styles[:bullet]}#{num}.#{base} #{l}"
                      else
                        "#{' ' * prefix.length}#{l}"
                      end
          end
          next
        end

        paragraph << line.strip
      end

      flush_paragraph.call
      result
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
  end
end
