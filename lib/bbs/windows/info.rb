# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative '../frame_buffer'
require_relative 'button_bar'

module BBS
  module Windows
    # A centered modal dialog for messages, splash screens, info displays.
    #
    #   BBS::Windows::Info.open(app,
    #     title: ' Welcome ',
    #     width: 70, height: 17,
    #     body: [
    #       { text: banner_line, style: :accent },
    #       "plain label with optional \e[1;33mraw ANSI\e[0m",
    #       :spacer,
    #       :rule,
    #       { kv: [['Online users', '5'], ['Ruby', RUBY_VERSION]] },
    #     ],
    #     buttons: [{ label: '&Continue', primary: true }]
    #   )
    #
    # When `scroll: true`, body items are flattened into a single ScrollView
    # filling the inner area. Use this for long, paginated content lists.
    #
    # Body item types:
    #   String                              → label with :window_text style
    #   :spacer | '' | nil                  → blank row
    #   :rule                               → horizontal ─── line
    #   { text:, style:, align: }           → styled label
    #   { kv: [[k, v], ...], label_width: } → key/value rows
    #   { widget:, height: }                → arbitrary widget (non-scroll only)
    #   BBS::Widget                         → as-is, 1 row (non-scroll only)
    #
    # Default buttons: a single centered `[ &Close ]` if `buttons:` is nil.
    class Info < Window
      DEFAULT_BUTTON  = [{ label: '&Close', cancel: true }].freeze
      DEFAULT_PADDING = { sides: 2, top: 1, bottom: 2 }.freeze

      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      attr_reader :scroll_view

      def initialize(app:, title:, body: [], buttons: nil, width: 60, height: nil,
                     scroll: false, padding: nil)
        super(title: title, modal: true)
        self.theme = app.theme
        @app     = app
        @body    = body
        @buttons = buttons.nil? ? DEFAULT_BUTTON.dup : Array(buttons)
        @scroll  = scroll
        @width   = width
        @height  = height
        @padding = DEFAULT_PADDING.merge(padding || {})
        build
      end

      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@primary_button) if @primary_button
        self
      end

      private

      def build
        button_h = @buttons.any? ? 2 : 0
        body_rows = @scroll ? 10 : @body.sum { |it| item_rows(it) }
        h = @height || (@padding[:top] + body_rows + button_h + @padding[:bottom])
        w = [@width, @app.cols - 4].min
        h = [h, @app.rows - 4].min
        x = (@app.cols - w) / 2 + 1
        y = (@app.rows - h) / 2 + 1
        layout(x, y, w, h)

        inner_w = w - @padding[:sides] * 2
        inner_x = bounds.x + @padding[:sides]
        inner_y = bounds.y + @padding[:top]
        body_h  = h - @padding[:top] - @padding[:bottom] - button_h
        body_h  = [body_h, 0].max

        if @scroll
          place_scroll_body(inner_x, inner_y, inner_w, body_h)
        else
          place_static_body(inner_x, inner_y, inner_w)
        end

        @primary_button = ButtonBar.attach(self, @app, @buttons)[:primary]
      end

      def item_rows(item)
        case item
        when :spacer, :rule, '', nil then 1
        when String                  then 1
        when Hash
          return item[:kv].length          if item[:kv]
          return item[:height] || 1        if item[:widget]
          1
        when BBS::Widget
          h = item.bounds.height
          h.positive? ? h : 1
        else 1
        end
      end

      def place_scroll_body(x, y, w, h)
        lines = []
        @body.each { |item| append_scroll_lines(lines, item, w) }
        @scroll_view = BBS::Widgets::ScrollView.new(lines: lines)
        @scroll_view.layout(x, y, w, h)
        add(@scroll_view)
      end

      def append_scroll_lines(lines, item, width)
        base = theme[:text]
        case item
        when :spacer, '', nil
          lines << ''
        when :rule
          lines << "#{theme[:label]}#{'─' * width}#{base}"
        when String
          lines << item
        when Hash
          if item[:kv]
            kw = item[:label_width] || default_kv_label_width(item[:kv])
            item[:kv].each do |k, v|
              lines << "#{theme[:input_label]}#{k.to_s.ljust(kw)}#{base}  #{v}"
            end
          elsif item[:text]
            sgr = item[:style] ? theme[item[:style]] : base
            lines << "#{sgr}#{item[:text]}#{base}"
          end
        when BBS::Widget
          raise ArgumentError, 'scroll mode does not support widget body items'
        end
      end

      def place_static_body(x, y, w)
        row = 0
        @body.each { |item| row += place_static_item(item, x, y + row, w) }
      end

      def place_static_item(item, x, y, w)
        case item
        when :spacer, '', nil
          1
        when :rule
          label = BBS::Widgets::Label.new(text: '─' * w, style_key: :label)
          label.layout(x, y, w, 1)
          add(label)
          1
        when String
          label = BBS::Widgets::Label.new(text: item, style_key: :window_text)
          label.layout(x, y, w, 1)
          add(label)
          1
        when Hash
          place_static_hash(item, x, y, w)
        when BBS::Widget
          h = item.bounds.height.positive? ? item.bounds.height : 1
          item.layout(x, y, w, h)
          add(item)
          h
        else
          1
        end
      end

      def place_static_hash(item, x, y, w)
        if item[:kv]
          kw = item[:label_width] || default_kv_label_width(item[:kv])
          item[:kv].each_with_index do |(k, v), i|
            label = BBS::Widgets::Label.new(text: k.to_s.ljust(kw), style_key: :input_label)
            label.layout(x, y + i, kw, 1)
            add(label)
            value = BBS::Widgets::Label.new(text: v.to_s, style_key: :window_text)
            value.layout(x + kw + 2, y + i, w - kw - 2, 1)
            add(value)
          end
          item[:kv].length
        elsif item[:widget]
          wd = item[:widget]
          h  = item[:height] || (wd.bounds.height.positive? ? wd.bounds.height : 1)
          wd.layout(x, y, w, h)
          add(wd)
          h
        elsif item[:text]
          label = BBS::Widgets::Label.new(
            text:      item[:text],
            style_key: item[:style] || :window_text,
            align:     item[:align] || :left
          )
          label.layout(x, y, w, 1)
          add(label)
          1
        else
          1
        end
      end

      def default_kv_label_width(pairs)
        max = pairs.map { |k, _| k.to_s.length }.max || 0
        [max + 1, 16].min.clamp(8, 16)
      end
    end
  end
end
