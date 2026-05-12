# frozen_string_literal: true

module BBS
  class TUIRunner
    def initialize(session, session_id, tui, context: {})
      @session    = session
      @session_id = session_id
      @tui        = tui
      @context    = context
    end

    def run
      ctx = Context.new(@session, @session_id, @tui)
      @context.each { |k, v| ctx.instance_variable_set(:"@#{k}", v) }
      ctx.instance_eval(&@tui.init_block) if @tui.init_block
      ctx.go(@tui.start_page)

      loop do
        ctx.do_render
        key = @session.readkey
        break if key.nil?
        break if ctx.dispatch_key(key) == :halt
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      @session.write("\e[?25h\e[2J\e[H")
    end

    class Context
      STYLES = FlowRunner::STYLES

      BG_COLORS = {
        black:  "\e[40m", red:    "\e[41m", green: "\e[42m",
        yellow: "\e[43m", blue:   "\e[44m", cyan:  "\e[46m",
        white:  "\e[47m",
      }.freeze

      def initialize(session, session_id, tui)
        @session          = session
        @session_id       = session_id
        @tui              = tui
        @current_page     = nil
        @committed_frame  = nil
        extend(@tui.helper_module) if @tui.helper_module
      end

      def go(page_name)
        @current_page = page_name
        page = @tui.pages[page_name]
        instance_eval(&page.enter_block) if page&.enter_block
        nil
      end

      def reload = go(@current_page)

      def do_render
        cols = term_cols
        rows = term_rows

        first_render = @committed_frame.nil?
        resized      = !first_render &&
                       (@committed_frame.cols != cols || @committed_frame.rows != rows)

        @committed_frame = FrameBuffer.new(cols, rows) if first_render || resized
        @next_frame      = FrameBuffer.new(cols, rows)

        instance_eval(&@tui.chrome_block) if @tui.chrome_block
        page = @tui.pages[@current_page]
        instance_eval(&page.render_block) if page&.render_block

        delta = @next_frame.diff(@committed_frame)

        if first_render || resized || !delta.empty?
          prefix = (first_render || resized) ? "\e[2J\e[H" : ""
          @session.write("\e[?25l#{prefix}#{delta}\e[?25h")
          @committed_frame = @next_frame
        end
      end

      def dispatch_key(key)
        page    = @tui.pages[@current_page]
        handler = page&.key_bindings&.[](key)

        if handler.nil? && key.is_a?(String) && key.length == 1
          if (ph = page&.key_bindings&.[](:printable))
            return instance_exec(key, &ph)
          end
        end

        return nil unless handler
        instance_eval(&handler)
      end

      # ── drawing primitives ──────────────────────────────────────────────────

      def clear
        @next_frame&.clear
      end

      def term_cols = @session.term_cols || 80
      def term_rows = @session.term_rows || 24

      def at(col, row)
        @next_frame.move(col, row)
      end

      def text(content, x: nil, y: nil, style: nil)
        at(x, y) if x && y
        @next_frame.write_ansi(content.to_s, base_sgr: resolve_style(style))
      end

      def bar(y:, content:, width: nil, style: :muted)
        width ||= term_cols
        sgr    = resolve_style(style)
        at 1, y
        @next_frame.write(' ' * width, sgr: sgr)
        at 1, y
        @next_frame.write_ansi(content.to_s, base_sgr: sgr)
      end

      def list(items, x:, y:, selected: nil, style: :muted, highlight: :success)
        norm = resolve_style(style)     || STYLES[:muted]
        hi   = resolve_style(highlight) || STYLES[:success]
        items.each_with_index do |item, i|
          at x, y + i
          if i == selected
            @next_frame.write("▶ ", sgr: hi)
            @next_frame.write_ansi(item.to_s, base_sgr: hi)
          else
            @next_frame.write("  ", sgr: norm)
            @next_frame.write_ansi(item.to_s, base_sgr: norm)
          end
        end
      end

      def fill(x:, y:, w:, h:, bg:)
        sgr = BG_COLORS.fetch(bg, bg.to_s)
        h.times do |dy|
          at x, y + dy
          @next_frame.write(' ' * w, sgr: sgr)
        end
      end

      def screen_fill(bg:)
        fill(x: 1, y: 1, w: term_cols, h: term_rows, bg: bg)
      end

      def box(x:, y:, w:, h:, title: nil, style: :muted, bg: nil)
        color  = resolve_style(style) || STYLES[:muted]
        inner  = w - 2
        bg_sgr = bg ? BG_COLORS.fetch(bg, bg.to_s) : nil

        at x, y
        if title
          prefix = "══ #{title} "
          pad    = [inner - prefix.length, 0].max
          @next_frame.write("╔#{prefix}#{'═' * pad}╗", sgr: color)
        else
          @next_frame.write("╔#{'═' * inner}╗", sgr: color)
        end

        (1...h - 1).each do |dy|
          at x, y + dy
          @next_frame.write('║', sgr: color)
          @next_frame.write(' ' * inner, sgr: bg_sgr)
          @next_frame.write('║', sgr: color)
        end

        at x, y + h - 1
        @next_frame.write("╚#{'═' * inner}╝", sgr: color)

        yield x + 1, y + 1, inner, h - 2 if block_given?
      end

      def float(title: nil, width: 40, height: 20, style: :muted, bg: :black, &block)
        w = [[width, term_cols - 4].min, 4].max
        h = [[height, term_rows - 4].min, 3].max
        x = (term_cols - w) / 2 + 1
        y = (term_rows - h) / 2 + 1
        box(x: x, y: y, w: w, h: h, title: title, style: style, bg: bg, &block)
      end

      private

      def resolve_style(style)
        case style
        when Symbol then STYLES[style]
        when String then style
        end
      end
    end
  end
end
