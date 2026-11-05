# frozen_string_literal: true

module BBS
  module Kit
    module Modern
      # The palette of the kit (bbs-web's): the accent green and the text,
      # dim, rule, warning and error colours, the lit row's background.
      module Palette
        # The accent by default.
        GREEN    = BBS::Style[fg: 84]
        # The words.
        TEXT     = BBS::Style[fg: 250]
        # A note, a hint.
        DIM      = BBS::Style[fg: 244]
        # A rule.
        LINE     = BBS::Style[fg: 238]
        # A warning.
        YELLOW   = BBS::Style[fg: 221]
        # An error.
        RED      = BBS::Style[fg: 203]
        # The background of the lit row.
        SELECTED = BBS::Style[bg: 235]
        # Bold.
        BOLD     = BBS::Style[bold: true]
        # Back to plain.
        RESET    = BBS::Style::RESET
      end

      # How a board's modern screens look:
      #
      # [logo]      lines of the logo over the tabs (none: no logo)
      # [tabs]      the tabs in order, key => label
      # [right]     the words at the right of the tabs
      # [accent]    the colour of the logo, the lit tab, the top line and
      #             the lit row's arrow
      # [crumb]     the first words of a screen's top line (#crumbs), or
      #             +nil+
      # [max_width] the most columns a screen takes
      # [margin]    the columns of air on the left
      Look = Data.define(:logo, :tabs, :right, :accent, :crumb, :max_width, :margin) do
        # A look; every part has its default.
        def initialize(
          logo: [],
          tabs: {},
          right: 'TAB switches',
          accent: Palette::GREEN,
          crumb: nil,
          max_width: 100,
          margin: 2
        )
          super
        end
      end

      # The look of a screen without one of its own.
      DEFAULT = Look.new

      # The helpers of a modern screen (Screen) and of a runner of them
      # (Tabs): the width and rows the screen gives, the margin, rules,
      # text fitted to a width with no control character, a menu row, the
      # logo and the tabs, the top line. The look comes from #look.
      module Style
        include Palette

        # The Look; the runner's (Tabs#look) on a page of one, else DEFAULT.
        def look
          runner = respond_to?(:pages) ? pages : nil
          runner.respond_to?(:look) ? runner.look : DEFAULT
        end

        # The columns of the screen, after the margin.
        def width = session.term_cols.clamp(40, look.max_width) - look.margin

        # The rows of the screen.
        def rows = session.term_rows.clamp(12, 200)

        # The margin as spaces.
        def pad = ' ' * look.margin

        # A rule across the width.
        def rule = "#{LINE}#{'─' * width}#{RESET}"

        # +text+ cut or padded to +size+ columns, an ellipsis where it was cut;
        # no control character of it reaches the caller.
        def fit(text, size)
          size = [size, 0].max
          text = plain(text)
          text.length > size ? "#{text[0, [size - 1, 0].max]}…" : text.ljust(size)
        end

        # +text+ on one line with no control or bidi character (BBS::Text.clean).
        def plain(text) = BBS::Text.clean(text, keep_newlines: false).tr("\t", ' ')

        # A row of a menu: +label+ in +size+ columns and +note+, lit with an
        # arrow when chosen.
        def menu_row(label, note, size, lit:)
          "#{lit ? "#{SELECTED}#{look.accent}▸ " : '  '}#{BOLD}#{fit(label, size)}#{RESET}" \
            "#{SELECTED if lit}#{DIM}#{fit(note, width - size - 2)}#{RESET}"
        end

        # The logo and the tabs, +tab+ lit, and a rule under them.
        def masthead(tab) = ['', *look.logo.map { |l| "#{look.accent}#{l}#{RESET}" }, tabs_line(tab), rule]

        # The tabs, +tab+ lit, and the look's words at the right.
        def tabs_line(tab)
          right = look.right.to_s
          "#{tab_labels(tab).join("#{LINE}│#{RESET}")}#{' ' * [tabs_room(right), 1].max}#{DIM}#{right}#{RESET}"
        end

        # The columns between the tabs and +right+.
        def tabs_room(right) = width - look.tabs.values.sum { |l| l.length + 2 } - (look.tabs.size - 1) - right.length

        # Each tab's label, +tab+ lit.
        def tab_labels(tab)
          look.tabs.map do |key, label|
            key == tab ? "#{SELECTED}#{look.accent}#{BOLD} #{label} #{RESET}" : "#{DIM} #{label} #{RESET}"
          end
        end

        # The top line of a screen: the look's crumb, +path+, and +right+.
        def crumbs(path, right = '')
          right = plain(right)
          left  = fit(crumb_words(path), width - right.length - 1).rstrip
          "#{look.accent}#{BOLD}#{left}#{RESET}#{' ' * [width - left.length - right.length, 1].max}#{DIM}#{right}#{RESET}"
        end

        # The words of the top line: the look's crumb and +path+.
        def crumb_words(path) = look.crumb ? "#{look.crumb} › #{path}" : path.to_s

        # A time (epoch seconds) as a date and time, or "never".
        def date(at) = at ? Time.at(at).strftime('%Y-%m-%d %H:%M') : 'never'
      end
    end
  end
end
