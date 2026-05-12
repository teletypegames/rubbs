# frozen_string_literal: true

module BBS
  class TUI
    module Helpers
      # ── Primitives ───────────────────────────────────────────────────────────

      def tc(style, str) = "#{THEME.fetch(style, THEME[:normal])}#{str}#{THEME[:reset]}"
      def cont_w         = term_cols - CONT_X - 1
      def cont_h         = term_rows - 4

      def fmt_date(iso)
        Time.parse(iso.to_s).strftime('%Y-%m-%d')
      rescue
        iso.to_s
      end

      def wordwrap(text, width)
        words = text.to_s
                    .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
                    .gsub(/[#*_`~>|\\]/, '')
                    .gsub(/\r?\n+/, ' ')
                    .strip
                    .split
        lines, line = [], +''
        words.each do |w|
          if    line.empty?                         then line << w
          elsif line.length + 1 + w.length <= width then line << ' ' << w
          else  lines << line.dup; line = +w
          end
        end
        lines << line unless line.empty?
        lines
      end

      # ── State ─────────────────────────────────────────────────────────────────

      def init_state
        @menu_sel   = 0
        @page_title = 'TELETYPE BBS'
        @items      = []
        @item_sel   = 0
        @scroll     = 0
        @detail     = []
        @page_meta  = +''
        @input      = +''
        @status     = +''
        @prev_page  = nil
      end

      # ── Data loaders ──────────────────────────────────────────────────────────

      def load_messages(service)
        @items  = service.recent(30).map { |m|
          "#{tc(:label, m.timestamp)} #{tc(:bright, m.username)}: #{m.text}"
        }
        @scroll = 0
      end

      def load_wiki_list(service, category)
        @items    = service.list(category)
        @item_sel = 0
        @scroll   = 0
      end

      def open_wiki_page(service, back:)
        return unless (page = @items[@item_sel])
        @detail     = wordwrap(service.content(page.id), cont_w)
        @page_title = page.title
        @page_meta  = "#{fmt_date(page.created_at)}  #{service.page_url(page.locale, page.path)}"
        @prev_page  = back
        @scroll     = 0
        go :page_view
      end

      # ── Chrome ────────────────────────────────────────────────────────────────

      def render_chrome
        screen_fill bg: :black
        panel_h = term_rows - 1

        box x: 1,          y: 1, w: LEFT_W,             h: panel_h,
            style: THEME[:border], bg: :black
        box x: LEFT_W + 1, y: 1, w: term_cols - LEFT_W, h: panel_h,
            title: " #{@page_title}  │  #{@username}  │  #{ONLINE.count} online ",
            style: THEME[:border], bg: :black

        list MENU_ITEMS.map { |i| i[0, LEFT_W - 4] },
             x: 2, y: CONT_Y,
             selected: @menu_sel,
             style: THEME[:normal], highlight: THEME[:selected]

        bar y: term_rows,
            content: "  \e[1;37;43m↑↓\e[0;30;43m Navigate  \e[1;37;43mEnter\e[0;30;43m Select  " \
                     "\e[1;37;43mQ\e[0;30;43m Back  \e[1;37;43mR\e[0;30;43m Refresh",
            style: THEME[:status]
      end

      # ── Page renderers ────────────────────────────────────────────────────────

      def render_messages
        (@items[@scroll, cont_h] || []).each_with_index do |line, i|
          text line[0, cont_w], x: CONT_X, y: CONT_Y + i
        end
        text "#{@items.size} msg(s)  ↑↓ scroll  r refresh  q back",
             x: CONT_X, y: CONT_Y + cont_h, style: THEME[:label]
      end

      def render_new_message_form
        text 'Type your message and press Enter.  Esc cancels.',
             x: CONT_X, y: CONT_Y, style: THEME[:normal]
        text "#{tc(:bright, @username)}: #{tc(:input, @input)}_",
             x: CONT_X, y: CONT_Y + 2
        text @status, x: CONT_X, y: CONT_Y + 4, style: THEME[:error] unless @status.empty?
      end

      def render_wiki_list
        list_h  = cont_h - 3
        visible = @items[@scroll, list_h] || []
        if visible.empty?
          text 'No items found.', x: CONT_X, y: CONT_Y, style: THEME[:normal]
        else
          list visible.map { |p| p.title[0, cont_w - 2] },
               x: CONT_X, y: CONT_Y,
               selected: @item_sel - @scroll,
               style: THEME[:normal], highlight: THEME[:selected]
          if (page = @items[@item_sel])
            hint = page.description.to_s.strip[0, cont_w]
            text hint, x: CONT_X, y: CONT_Y + cont_h - 2, style: THEME[:normal] unless hint.empty?
          end
        end
        text '↑↓ navigate  Enter read  r refresh  q back',
             x: CONT_X, y: CONT_Y + cont_h, style: THEME[:label]
      end

      def render_page_view
        text @page_meta[0, cont_w], x: CONT_X, y: CONT_Y, style: THEME[:label]
        (@detail[@scroll, cont_h - 2] || []).each_with_index do |l, i|
          text l[0, cont_w], x: CONT_X, y: CONT_Y + 2 + i, style: THEME[:normal]
        end
        text "#{@scroll + 1}/#{@detail.size}  ↑↓ scroll  q back",
             x: CONT_X, y: CONT_Y + cont_h, style: THEME[:label]
      end

      def render_game_card
        if @items.empty?
          text 'No games found.', x: CONT_X, y: CONT_Y, style: THEME[:normal]
          return
        end
        game  = @items[@item_sel]
        links = game.external_links

        text "#{@item_sel + 1}/#{@items.size}  #{game.title}"[0, cont_w],
             x: CONT_X, y: CONT_Y, style: THEME[:bright]
        text "#{game.platform}  ·  #{game.author}"[0, cont_w],
             x: CONT_X, y: CONT_Y + 1, style: THEME[:normal]

        story_rows = cont_h - 4 - links.size
        wordwrap(game.story, cont_w).first(story_rows).each_with_index do |l, i|
          text l, x: CONT_X, y: CONT_Y + 3 + i, style: THEME[:normal]
        end

        link_y = CONT_Y + cont_h - links.size
        links.each_with_index do |lnk, i|
          text "#{tc(:label, lnk[:label])}  #{lnk[:url]}"[0, cont_w],
               x: CONT_X, y: link_y + i
        end

        text '↑↓ navigate  r refresh  q back',
             x: CONT_X, y: CONT_Y + cont_h, style: THEME[:label]
      end

      def render_online_users
        @items.each_with_index do |uname, i|
          you = uname == @username ? tc(:label, ' ← you') : ''
          text tc(:bright, uname) + you, x: CONT_X, y: CONT_Y + i
        end
        text "#{@items.size} user(s) online  r refresh  q back",
             x: CONT_X, y: CONT_Y + cont_h, style: THEME[:label]
      end

    end
  end
end
