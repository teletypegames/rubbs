# frozen_string_literal: true

module BBS
  class TUIRunner
    def initialize(session, session_id, tui)
      @session    = session
      @session_id = session_id
      @tui        = tui
    end

    def run
      ctx = Context.new(@session, @session_id)
      ctx.instance_eval(&@tui.init_block) if @tui.init_block

      loop do
        ctx.do_render(@tui.render_block) if @tui.render_block

        key = @session.readkey
        break if key.nil?

        handler = @tui.key_bindings[key]
        next unless handler

        result = handler.is_a?(Symbol) ? handler : ctx.instance_eval(&handler)
        break if result == :halt
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      @session.write("\e[?25h\e[2J\e[H")
    end

    class Context
      STYLES = FlowRunner::STYLES

      def initialize(session, session_id)
        @session    = session
        @session_id = session_id
        @buf        = +""
      end

      def do_render(block)
        @buf = +"\e[?25l"
        instance_eval(&block)
        @buf << "\e[?25h"
        @session.write(@buf)
      end

      # ── drawing primitives ────────────────────────────────────────────────

      def clear
        @buf << "\e[2J\e[H"
      end

      def at(col, row)
        @buf << "\e[#{row};#{col}H"
      end

      def text(content, x: nil, y: nil, style: nil)
        at(x, y) if x && y
        color = STYLES[style]
        @buf << (color ? "#{color}#{content}\e[0m" : content.to_s)
      end

      def bar(y:, content:, width: 80, style: :muted)
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
