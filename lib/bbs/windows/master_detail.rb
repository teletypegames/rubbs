# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative 'button_bar'

module BBS
  module Windows
    # A two-pane browser: left ListBox of items, right ScrollView of details.
    # Selecting an item in the list reloads the detail pane.
    #
    #   BBS::Windows::MasterDetail.open(app,
    #     title: ' Game Catalog ',
    #     items: services[:games].all,
    #     item_label: ->(g) { g.title },
    #     list_width: 30,
    #     render_detail: ->(game, width) { GameCard.lines(game, width) },
    #     actions: [
    #       { label: '&New', on_click: ->(win) { ... } }
    #     ],
    #     bottom_meta: ->(item) { "...optional 1-line meta..." }
    #   )
    #
    # `render_detail` is called with `(item, width)` whenever the selection
    # changes and on first paint. It must return an Array of strings (each one
    # is one rendered line; ANSI is supported). Returning nil shows nothing.
    #
    # `bottom_meta` is optional; if given, it's a `->(item) { text }` lambda
    # for a single info line below the detail pane.
    #
    # `actions:` are extra buttons (right-aligned by default). A `Close` button
    # is always appended on the right unless the caller suppresses it via
    # `close_button: false`.
    class MasterDetail < Window
      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      attr_reader :list_widget, :detail_view, :meta_label

      def initialize(app:, title:, items:, item_label:, render_detail:,
                     list_width: nil, bottom_meta: nil, actions: nil,
                     close_button: true, close_label: '&Close',
                     empty_message: '  (empty)',
                     width: nil, height: nil)
        super(title: title, modal: true)
        self.theme = app.theme
        @app           = app
        @items         = items
        @item_label    = item_label
        @render_detail = render_detail
        @bottom_meta   = bottom_meta
        @actions       = (actions || []).dup
        @actions << { label: close_label, cancel: true } if close_button
        @list_width    = list_width
        @empty_message = empty_message
        @width         = width
        @height        = height
        build
      end

      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@list_widget) if @list_widget
        reload_detail
        self
      end

      def reload_detail
        item = @list_widget&.selected_item
        if item.nil?
          @detail_view.lines  = [@empty_message]
          @detail_view.scroll = 0
          @meta_label.text    = '' if @meta_label
        else
          lines = @render_detail.call(item, @detail_view.bounds.width - 1)
          @detail_view.lines  = Array(lines)
          @detail_view.scroll = 0
          @meta_label.text    = @bottom_meta.call(item) if @meta_label && @bottom_meta
        end
      end

      private

      def build
        w = @width  || @app.cols - 4
        h = @height || @app.rows - 6
        x = (@app.cols - w) / 2 + 1
        y = (@app.rows - h) / 2 + 1
        layout(x, y, w, h)

        has_buttons = !@actions.empty?
        has_meta    = !@bottom_meta.nil?
        panel_h     = h - 4 - (has_meta ? 1 : 0) - (has_buttons ? 1 : 0)
        panel_h     = [panel_h, 3].max

        list_w = @list_width || [(w / 3).clamp(20, 40), w - 10].min
        list_x = bounds.x + 2
        list_y = bounds.y + 2

        @list_widget = BBS::Widgets::ListBox.new(
          items: @items,
          label: ->(item) { "  #{@item_label.call(item)}".ljust(list_w) }
        )
        @list_widget.layout(list_x, list_y, list_w, panel_h)
        add(@list_widget)

        detail_x = list_x + list_w + 2
        detail_w = bounds.width - list_w - 5
        @detail_view = BBS::Widgets::ScrollView.new(lines: [])
        @detail_view.layout(detail_x, list_y, detail_w, panel_h)
        add(@detail_view)

        if has_meta
          meta_y = bounds.y + h - (has_buttons ? 3 : 2)
          @meta_label = BBS::Widgets::Label.new(text: '', style_key: :input_label)
          @meta_label.layout(bounds.x + 2, meta_y, bounds.width - 4, 1)
          add(@meta_label)
        end

        @list_widget.on_select = ->(_, _) { reload_detail }

        ButtonBar.attach(self, @app, @actions)
      end
    end
  end
end
