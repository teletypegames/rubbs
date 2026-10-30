# frozen_string_literal: true

require_relative '../widget'

module BBS
  module Widgets
    # AnsiArt: renders a CP437 / ANSI art file (or any pre-encoded ASCII art)
    # into a region of the screen.
    #
    #   art = BBS::Widgets::AnsiArt.from_file('art/welcome.ans')
    #   art.layout(1, 2, 80, 22)
    #   container.add(art)
    #
    # File handling:
    #
    # [.ans, .asc, .nfo]    decoded as IBM437 to UTF-8
    # [.ansi, .txt]         assumed to already be UTF-8 (or 7-bit ASCII +
    #                       ANSI escapes)
    # [any other extension] tries UTF-8 first, falls back to IBM437
    #
    # Everything from the first \x1A (SUB) byte on, the SAUCE metadata
    # included, is stripped.
    #
    # Layout options:
    #
    # [align]       +:center+ (default), +:left+ or +:right+: horizontal
    #               placement
    # [valign]      +:middle+ (default), +:top+ or +:bottom+: vertical
    #               placement
    # [fill_parent] take the parent's bounds on every render (default true)
    #
    # The art is placed as one block, by its widest line, so the lines keep
    # their columns. Lines wider or more than the bounds are clipped.
    #
    # See AnsiArt.random(dir) for picking a random file from a directory.
    class AnsiArt < Widget
      # The art lines (Strings with ANSI escapes), the widest line's visible
      # width, the number of lines, the horizontal and vertical alignment,
      # and whether the widget takes its parent's bounds. The widths are
      # computed by AnsiArt.new and not updated when +lines+ is set.
      attr_accessor :lines, :art_width, :art_height, :align, :valign, :fill_parent

      # Creates the widget from +lines+, an Array of String. Other keywords
      # go to Widget.new.
      def initialize(lines: [], align: :center, valign: :middle, fill_parent: true, **kw)
        super(**kw)
        @lines       = lines
        @align       = align
        @valign      = valign
        @fill_parent = fill_parent
        @art_width   = (lines.map { |l| visible_length(l) }.max || 0)
        @art_height  = lines.size
      end

      # Creates the widget from the art file at +path+ (see the file handling
      # above). +opts+ go to AnsiArt.new. Raises SystemCallError when the file
      # cannot be read.
      def self.from_file(path, **opts)
        new(lines: load_file(path), **opts)
      end

      # Creates the widget from +text+, split into lines at CR, LF or CRLF.
      # +opts+ go to AnsiArt.new.
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

      # Returns the lines of the built-in art used when no file is available.
      def self.default_lines
        built_in_fallback
      end

      # Draws the art into +frame+ within the bounds (the parent's when
      # +fill_parent+ is set), aligned and clipped, on the theme's +:text+
      # style.
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

        block_width = [@lines.map { |l| visible_length(l) }.max || 0, bounds.width].min
        @lines.first(visible_h).each_with_index do |line, i|
          clipped, = clip_line(line, bounds.width)
          x_offset = case @align
                     when :left   then 0
                     when :right  then [bounds.width - block_width, 0].max
                     else              [(bounds.width - block_width) / 2, 0].max
                     end
          frame.move(bounds.x + x_offset, bounds.y + y_offset + i)
          frame.write_ansi(clipped, base_sgr: style(:text))
        end
      end

      # The keys that scroll AnsiArt.view instead of leaving it.
      VIEW_SCROLL_KEYS = %i[up down page_up page_down home end].freeze

      # Shows art on the whole screen, the way an art viewer of the old boards
      # did: centred when it fits, scrolled with the arrows, PgUp/PgDn,
      # Home/End when it is taller than the screen, a status line at the
      # bottom. Any other key (or a click) returns. Run it inside
      # Application#with_line, which repaints the application afterwards:
      #
      #   app.with_line { |session| BBS::Widgets::AnsiArt.view(session, lines, title: 'sunset.ans') }
      #
      # Returns nil when the caller hung up, else true.
      def self.view(session, lines, title: nil)
        top = 0
        loop do
          cols   = session.term_cols || 80
          rows   = session.term_rows || 24
          view_h = [rows - 1, 1].max
          top    = top.clamp(0, [lines.size - view_h, 0].max)
          session.write(view_frame(lines, top, cols, rows, view_h, title))
          key = session.readkey
          return nil if key.nil?

          case key
          when :up        then top -= 1
          when :down      then top += 1
          when :page_up   then top -= view_h - 1
          when :page_down then top += view_h - 1
          when :home      then top = 0
          when :end       then top = lines.size
          when Telnet::MouseEvent
            next unless key.kind == :press

            return true
          else return true
          end
        end
      end

      # Returns the escape sequences that draw one screen of AnsiArt.view:
      # +view_h+ of +lines+ from index +top+, centred on a +cols+ x +rows+
      # screen, with the status line (+title+ and position) on the last row.
      def self.view_frame(lines, top, cols, rows, view_h, title)
        width  = lines.map { |l| FrameBuffer.visible_width(l) }.max || 0
        left   = [(cols - width) / 2, 0].max
        shown  = lines[top, view_h] || []
        offset = [(view_h - lines.size) / 2, 0].max
        out = +"\e[?25l\e[0m\e[2J"
        shown.each_with_index do |line, i|
          out << "\e[#{offset + i + 1};#{left + 1}H" << FrameBuffer.clip_ansi(line, cols - left) << "\e[0m"
        end
        more   = lines.size > view_h ? "  #{top + 1}-#{top + shown.size}/#{lines.size}  ↑↓ PgUp PgDn" : ''
        status = " #{title}#{more}  · any other key returns "
        out << "\e[#{rows};1H\e[0;30;47m" << FrameBuffer.clip_ansi(status, cols).ljust(cols) << "\e[0m\e[?25h"
      end

      # ── File loading ────────────────────────────────────────────────────────

      # Reads the art file at +path+, strips the SAUCE part, transcodes it to
      # UTF-8, and returns its lines. Raises SystemCallError when the file
      # cannot be read.
      def self.load_file(path)
        raw = File.binread(path)
        raw = strip_sauce(raw)
        text = transcode(raw, path)
        split_lines(text)
      end

      # The SAUCE record of an art file: +title+, +author+, +group+, and
      # +date+ as <tt>YYYY-MM-DD</tt> (empty when missing).
      Sauce = Struct.new(:title, :author, :group, :date, keyword_init: true)

      # The SAUCE record of an art file (title, author, group, date), or nil
      # when the file has none. Read from the last 128 bytes, CP437.
      def self.sauce(path)
        File.open(path, 'rb') do |f|
          return nil if f.size < 128
          f.seek(-128, IO::SEEK_END)
          record = f.read(128)
          return nil unless record.start_with?('SAUCE00')

          field = ->(from, length) do
            record.byteslice(from, length).force_encoding('IBM437')
                  .encode('UTF-8', invalid: :replace, undef: :replace).delete("\0").strip
          end
          date = field.call(82, 8)
          Sauce.new(title: field.call(7, 35), author: field.call(42, 20), group: field.call(62, 20),
                    date: date =~ /\A\d{8}\z/ ? "#{date[0, 4]}-#{date[4, 2]}-#{date[6, 2]}" : '')
        end
      rescue SystemCallError
        nil
      end

      # Returns +bytes+ cut before the first \x1A (SUB) byte, or unchanged
      # when there is none.
      def self.strip_sauce(bytes)
        sub = bytes.index("\x1A".b)
        sub ? bytes.byteslice(0, sub) : bytes
      end

      # Returns +bytes+ as a UTF-8 String, decoded by the extension of +path+
      # (see the file handling above); undecodable bytes are replaced.
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

      # Splits +text+ into an Array of lines at CR, LF or CRLF, keeping
      # trailing empty lines.
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
