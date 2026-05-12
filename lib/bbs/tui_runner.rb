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
      context = Context.new(@session, @session_id, @tui)
      @context.each { |key, value| context.instance_variable_set(:"@#{key}", value) }
      context.instance_eval(&@tui.init_block) if @tui.init_block
      context.go(@tui.start_page)

      loop do
        context.do_render
        key = @session.readkey
        break if key.nil?
        break if context.dispatch_key(key) == :halt
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      @session.write("\e[?25h\e[2J\e[H")
    end

    class Context
      STYLES = FlowRunner::STYLES

      BACKGROUND_COLORS = {
        black:  "\e[40m", red:    "\e[41m", green: "\e[42m",
        yellow: "\e[43m", blue:   "\e[44m", cyan:  "\e[46m",
        white:  "\e[47m",
      }.freeze

      def initialize(session, session_id, tui)
        @session         = session
        @session_id      = session_id
        @tui             = tui
        @current_page    = nil
        @committed_frame = nil
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
        columns = term_cols
        rows    = term_rows

        first_render = @committed_frame.nil?
        resized      = !first_render &&
                       (@committed_frame.cols != columns || @committed_frame.rows != rows)

        @committed_frame = FrameBuffer.new(columns, rows) if first_render || resized
        @next_frame      = FrameBuffer.new(columns, rows)

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
          if (printable_handler = page&.key_bindings&.[](:printable))
            return instance_exec(key, &printable_handler)
          end
        end

        return nil unless handler
        instance_eval(&handler)
      end

      # ── Drawing primitives ────────────────────────────────────────────────────

      def clear
        @next_frame&.clear
      end

      def term_cols = @session.term_cols || 80
      def term_rows = @session.term_rows || 24

      def at(column, row)
        @next_frame.move(column, row)
      end

      def text(content, x: nil, y: nil, style: nil)
        at(x, y) if x && y
        @next_frame.write_ansi(content.to_s, base_sgr: resolve_style(style))
      end

      def bar(y:, content:, width: nil, style: :muted)
        width ||= term_cols
        style_code = resolve_style(style)
        at 1, y
        @next_frame.write(' ' * width, sgr: style_code)
        at 1, y
        @next_frame.write_ansi(content.to_s, base_sgr: style_code)
      end

      def list(items, x:, y:, selected: nil, style: :muted, highlight: :success)
        normal_style    = resolve_style(style)     || STYLES[:muted]
        highlight_style = resolve_style(highlight) || STYLES[:success]
        items.each_with_index do |item, index|
          at x, y + index
          if index == selected
            @next_frame.write("▶ ", sgr: highlight_style)
            @next_frame.write_ansi(item.to_s, base_sgr: highlight_style)
          else
            @next_frame.write("  ", sgr: normal_style)
            @next_frame.write_ansi(item.to_s, base_sgr: normal_style)
          end
        end
      end

      def fill(x:, y:, width:, height:, background:)
        background_code = BACKGROUND_COLORS.fetch(background, background.to_s)
        height.times do |row_offset|
          at x, y + row_offset
          @next_frame.write(' ' * width, sgr: background_code)
        end
      end

      def screen_fill(background:)
        fill(x: 1, y: 1, width: term_cols, height: term_rows, background: background)
      end

      def box(x:, y:, width:, height:, title: nil, style: :muted, background: nil)
        style_code      = resolve_style(style) || STYLES[:muted]
        inner_width     = width - 2
        background_code = background ? BACKGROUND_COLORS.fetch(background, background.to_s) : nil

        at x, y
        if title
          prefix  = "══ #{title} "
          padding = [inner_width - prefix.length, 0].max
          @next_frame.write("╔#{prefix}#{'═' * padding}╗", sgr: style_code)
        else
          @next_frame.write("╔#{'═' * inner_width}╗", sgr: style_code)
        end

        (1...height - 1).each do |row_offset|
          at x, y + row_offset
          @next_frame.write('║', sgr: style_code)
          @next_frame.write(' ' * inner_width, sgr: background_code)
          @next_frame.write('║', sgr: style_code)
        end

        at x, y + height - 1
        @next_frame.write("╚#{'═' * inner_width}╝", sgr: style_code)

        yield x + 1, y + 1, inner_width, height - 2 if block_given?
      end

      def float(title: nil, width: 40, height: 20, style: :muted, background: :black, &block)
        clamped_width  = [[width,  term_cols - 4].min, 4].max
        clamped_height = [[height, term_rows - 4].min, 3].max
        x = (term_cols - clamped_width)  / 2 + 1
        y = (term_rows - clamped_height) / 2 + 1
        box(x: x, y: y, width: clamped_width, height: clamped_height,
            title: title, style: style, background: background, &block)
      end

      # ── Text utilities ────────────────────────────────────────────────────────

      def wordwrap(text, width)
        words = text.to_s
                    .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
                    .gsub(/[#*_`~>|\\]/, '')
                    .gsub(/\r?\n+/, ' ')
                    .strip
                    .split
        lines       = []
        current     = +''
        words.each do |word|
          if    current.empty?                               then current << word
          elsif current.length + 1 + word.length <= width   then current << ' ' << word
          else  lines << current.dup; current = +word
          end
        end
        lines << current unless current.empty?
        lines
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
