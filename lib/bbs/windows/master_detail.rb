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
    #
    # `on_activate` is optional: `->(item, window) { ... }`, called when the
    # caller presses Enter on a list item. `replace_items` swaps the list in
    # place (a file browser changing folders) and selects the first item.
    class MasterDetail < Window
      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      attr_reader :list_widget, :detail_view, :meta_label

      def initialize(app:, title:, items:, item_label:, render_detail:,
                     list_width: nil, bottom_meta: nil, actions: nil, on_activate: nil,
                     close_button: true, close_label: '&Close',
                     empty_message: '  (empty)',
                     width: nil, height: nil, maximizable: false)
        super(title: title, modal: true, maximizable: maximizable)
        self.theme = app.theme
        @app           = app
        @items         = items
        @item_label    = item_label
        @render_detail = render_detail
        @bottom_meta   = bottom_meta
        @on_activate   = on_activate
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

      def reload_detail(keep_scroll: false)
        item = @list_widget&.selected_item
        if item.nil?
          @detail_view.lines  = [@empty_message]
          @detail_view.scroll = 0
          @meta_label.text    = '' if @meta_label
        else
          scroll = keep_scroll ? @detail_view.scroll : 0
          lines  = Array(@render_detail.call(item, @detail_view.bounds.width - 1))
          @detail_view.lines  = lines
          @detail_view.scroll = scroll.clamp(0, [lines.size - @detail_view.bounds.height, 0].max)
          @meta_label.text    = @bottom_meta.call(item) if @meta_label && @bottom_meta
        end
      end

      def replace_items(items, title: nil)
        @items = items
        @list_widget.items    = items
        @list_widget.selected = 0
        @list_widget.scroll   = 0
        self.title = title if title
        reload_detail
      end

      def resizable? = true

      def normal_rect
        w = @width  || @app.cols - 4
        h = @height || @app.rows - 6
        [(@app.cols - w) / 2 + 1, (@app.rows - h) / 2 + 1, w, h]
      end

      # Lays the window out at the given size (terminal resized, maximized,
      # restored) and re-renders the detail at the new pane width.
      def place(x, y, width, height)
        layout(x, y, width, height)
        place_panes
        ButtonBar.place(self, @bar[:widgets], @actions)
        list = @list_widget
        list.scroll = [list.selected - list.bounds.height + 1, 0].max if list.selected >= list.scroll + list.bounds.height
        reload_detail(keep_scroll: true)
      end

      private

      def build
        place_window

        @list_widget = BBS::Widgets::ListBox.new(
          items: @items,
          label: ->(item) { "  #{@item_label.call(item)}".ljust(@list_w || 0) }
        )
        add(@list_widget)

        @detail_view = BBS::Widgets::ScrollView.new(lines: [])
        add(@detail_view)

        unless @bottom_meta.nil?
          @meta_label = BBS::Widgets::Label.new(text: '', style_key: :input_label)
          add(@meta_label)
        end

        @list_widget.on_select = ->(_, _) { reload_detail }
        if @on_activate
          @list_widget.on_activate = lambda do |item, _|
            @on_activate.call(item, self) if item
            :handled
          end
        end

        @bar = ButtonBar.attach(self, @app, @actions)
        place_panes
      end

      def place_window
        layout(*normal_rect)
      end

      def place_panes
        h           = bounds.height
        has_buttons = !@actions.empty?
        has_meta    = !@meta_label.nil?
        panel_h     = h - 4 - (has_meta ? 1 : 0) - (has_buttons ? 1 : 0)
        panel_h     = [panel_h, 3].max

        @list_w = @list_width || [(bounds.width / 3).clamp(20, 40), bounds.width - 10].min
        @list_w = @list_w.clamp(1, [bounds.width / 2, 1].max)
        list_x  = bounds.x + 2
        list_y  = bounds.y + 2
        @list_widget.layout(list_x, list_y, @list_w, panel_h)

        detail_x = list_x + @list_w + 2
        detail_w = [bounds.width - @list_w - 5, 1].max
        @detail_view.layout(detail_x, list_y, detail_w, panel_h)

        if @meta_label
          meta_y = bounds.y + h - (has_buttons ? 3 : 2)
          @meta_label.layout(bounds.x + 2, meta_y, bounds.width - 4, 1)
        end
      end
    end
  end
end
