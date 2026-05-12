# frozen_string_literal: true

require_relative '../widget'

module BBS
  module Widgets
    # AnsiArt — render a CP437 / ANSI art file (or any pre-encoded ASCII art)
    # into a region of the screen.
    #
    #   art = BBS::Widgets::AnsiArt.from_file('art/welcome.ans')
    #   art.layout(1, 2, 80, 22)
    #   container.add(art)
    #
    # File handling:
    #   .ans / .asc / .nfo  → decoded as IBM437 → UTF-8
    #   .ansi / .txt         → assumed to already be UTF-8 (or 7-bit ASCII +
    #                          ANSI escapes)
    #   any other extension  → tries UTF-8 first, falls back to IBM437
    #
    # SAUCE metadata (last 129 bytes, marked by \x1A SUB) is stripped.
    #
    # Layout options:
    #   align: :center (default), :left, :right    — horizontal placement
    #   valign: :middle (default), :top, :bottom   — vertical placement
    #   width  — clip art to this many visible columns (default: auto)
    #
    # See AnsiArt.random(dir) for picking a random file from a directory.
    class AnsiArt < Widget
      attr_accessor :lines, :art_width, :art_height, :align, :valign, :fill_parent

      def initialize(lines: [], align: :center, valign: :middle, fill_parent: true, **kw)
        super(**kw)
        @lines       = lines
        @align       = align
        @valign      = valign
        @fill_parent = fill_parent
        @art_width   = (lines.map { |l| visible_length(l) }.max || 0)
        @art_height  = lines.size
      end

      def self.from_file(path, **opts)
        new(lines: load_file(path), **opts)
      end

      def self.from_string(text, **opts)
        new(lines: split_lines(text), **opts)
      end

      # Pick a random file from +dir+. Returns a built-in fallback if the
      # directory is missing or empty.
      def self.random(dir, **opts)
        files = Dir.glob(File.join(dir, '*.{ans,ansi,asc,nfo,txt}')).reject { |f| File.directory?(f) }
        return new(lines: built_in_fallback, **opts) if files.empty?
        from_file(files.sample, **opts)
      rescue StandardError
        new(lines: built_in_fallback, **opts)
      end

      def self.default_lines
        built_in_fallback
      end

      def render(frame)
        return if @lines.empty?
        if @fill_parent && parent && parent.bounds
          @bounds = parent.bounds.dup
        end
        return if bounds.width <= 0 || bounds.height <= 0

        visible_h = [@art_height, bounds.height].min
        y_offset = case @valign
                   when :top    then 0
                   when :bottom then [bounds.height - visible_h, 0].max
                   else              [(bounds.height - visible_h) / 2, 0].max
                   end

        @lines.first(visible_h).each_with_index do |line, i|
          line_width = visible_length(line)
          clipped, clipped_width = clip_line(line, bounds.width)
          x_offset = case @align
                     when :left   then 0
                     when :right  then [bounds.width - clipped_width, 0].max
                     else              [(bounds.width - clipped_width) / 2, 0].max
                     end
          frame.move(bounds.x + x_offset, bounds.y + y_offset + i)
          frame.write_ansi(clipped, base_sgr: style(:text))
        end
      end

      # ── File loading ────────────────────────────────────────────────────────
      def self.load_file(path)
        raw = File.binread(path)
        raw = strip_sauce(raw)
        text = transcode(raw, path)
        split_lines(text)
      end

      def self.strip_sauce(bytes)
        sub = bytes.index("\x1A".b)
        sub ? bytes.byteslice(0, sub) : bytes
      end

      def self.transcode(bytes, path)
        ext = File.extname(path).downcase
        case ext
        when '.ans', '.asc', '.nfo'
          bytes.force_encoding('IBM437').encode('UTF-8', invalid: :replace, undef: :replace)
        when '.ansi', '.txt'
          bytes.force_encoding('UTF-8').scrub('?')
        else
          # try utf8 first
          utf8 = bytes.dup.force_encoding('UTF-8')
          utf8.valid_encoding? ? utf8 : bytes.force_encoding('IBM437').encode('UTF-8',
            invalid: :replace, undef: :replace)
        end
      end

      def self.split_lines(text)
        text.gsub(/\r\n?/, "\n").split("\n", -1)
      end

      # Strip ANSI escapes and count visible characters.
      def visible_length(line)
        line.gsub(/\e\[[\d;?]*[A-Za-z]/, '').length
      end

      # Clip the visible portion of a line that may contain ANSI escapes.
      def clip_line(line, max_visible)
        visible = 0
        out     = +''
        i       = 0
        s       = line
        while i < s.length
          ch = s[i]
          if ch == "\e" && s[i + 1] == '['
            j = i + 2
            j += 1 while j < s.length && !s[j].match?(/[A-Za-z]/)
            out << s[i..j] if j < s.length
            i = j + 1
          else
            break if visible >= max_visible
            out << ch
            visible += 1
            i += 1
          end
        end
        [out, visible]
      end

      # Default art used when no file is configured / available.
      def self.built_in_fallback
        sgr = ->(code) { "\e[#{code}m" }
        y  = sgr.call('1;33')
        d  = sgr.call('0;33')
        c  = sgr.call('1;36')
        r  = sgr.call('0')
        [
          '',
          "#{y}     ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄#{r}",
          "#{y}    █#{d}░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}╔══════════════════════════════════════════════╗#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}║   #{y}▀█▀ █▀▀ █   █▀▀ ▀█▀ █▄█ █▀█ █▀▀  █▀▄ █▀▄ █▀#{c}   ║#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}║   #{y} █  ██▄ █▄▄ ██▄  █   █  █▀▀ ██▄  █▄▀ █▄▀ ▄█#{c}   ║#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}║                                              ║#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}║         #{r}an open call to old friends#{c}            ║#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}║                                              ║#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░ #{c}╚══════════════════════════════════════════════╝#{d} ░#{y}█#{r}",
          "#{y}    █#{d}░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░#{y}█#{r}",
          "#{y}     ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀#{r}",
          '',
          "          #{d}F10#{r}  open the top menu   #{d}F1#{r}  help",
          "          #{d}F2#{r}   message boards      #{d}F4#{r}  chat",
        ]
      end
    end
  end
end
