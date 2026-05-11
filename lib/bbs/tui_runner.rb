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

      def initialize(session, session_id, tui)
        @session      = session
        @session_id   = session_id
        @tui          = tui
        @current_page = nil
        @buf          = +""
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
        @buf = +"\e[?25l"
        clear
        instance_eval(&@tui.chrome_block) if @tui.chrome_block
        page = @tui.pages[@current_page]
        instance_eval(&page.render_block) if page&.render_block
        @buf << "\e[?25h"
        @session.write(@buf)
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

      def clear     = @buf << "\e[2J\e[H"
      def term_cols = @session.term_cols || 80
      def term_rows = @session.term_rows || 24

      def at(col, row)
        @buf << "\e[#{row};#{col}H"
      end

      def text(content, x: nil, y: nil, style: nil)
        at(x, y) if x && y
        color = STYLES[style]
        @buf << (color ? "#{color}#{content}\e[0m" : content.to_s)
      end

      def bar(y:, content:, width: nil, style: :muted)
        width ||= term_cols
        text content.to_s.ljust(width), x: 1, y: y, style: style
      end

      def list(items, x:, y:, selected: nil, style: :muted, highlight: :success)
        norm = STYLES.fetch(style, STYLES[:muted])
        hi   = STYLES.fetch(highlight, STYLES[:success])
        items.each_with_index do |item, i|
          at x, y + i
          @buf << (i == selected ? "#{hi}▶ #{item}\e[0m" : "#{norm}  #{item}\e[0m")
        end
      end

      def box(x:, y:, w:, h:, title: nil, style: :muted)
        color = STYLES.fetch(style, STYLES[:muted])
        inner = w - 2

        at x, y
        if title
          prefix = "══ #{title} "
          fill   = [inner - prefix.length, 0].max
          @buf << "#{color}╔#{prefix}#{'═' * fill}╗\e[0m"
        else
          @buf << "#{color}╔#{'═' * inner}╗\e[0m"
        end

        (1...h - 1).each do |dy|
          at x, y + dy
          @buf << "#{color}║\e[0m#{' ' * inner}#{color}║\e[0m"
        end

        at x, y + h - 1
        @buf << "#{color}╚#{'═' * inner}╝\e[0m"

        yield x + 1, y + 1, inner, h - 2 if block_given?
      end
    end
  end
end
