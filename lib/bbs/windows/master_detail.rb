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
    # +render_detail+ is called with <tt>(item, width)</tt> whenever the
    # selection changes and on first paint. It must return an Array of
    # strings (each one is one rendered line; ANSI is supported). Returning
    # nil shows nothing.
    #
    # +bottom_meta+ is optional; if given, it's a <tt>->(item) { text }</tt>
    # lambda for a single info line below the detail pane.
    #
    # <tt>actions:</tt> are extra buttons (right-aligned by default). A
    # +Close+ button is always appended on the right unless the caller
    # suppresses it via <tt>close_button: false</tt>.
    #
    # +on_activate+ is optional: <tt>->(item, window) { ... }</tt>, called
    # when the caller presses Enter on a list item. #replace_items swaps the
    # list in place (a file browser changing folders) and selects the first
    # item.
    class MasterDetail < Window
      # Creates a master/detail window with the keywords of MasterDetail.new
      # and opens it on +app+.
      #
      # Returns the MasterDetail window.
      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      # The BBS::Widgets::ListBox of items, the BBS::Widgets::ScrollView of
      # details, and the BBS::Widgets::Label of the meta line (+nil+ without
      # +bottom_meta+).
      attr_reader :list_widget, :detail_view, :meta_label

      # Creates the window and its panes, centred on +app+'s screen. It is
      # not opened; see #attach.
      #
      # [app]           the BBS::Application
      # [title]         the window title
      # [items]         the Array of items in the list
      # [item_label]    called with an item, returns its list text
      # [render_detail] called with <tt>(item, width)</tt>, returns the
      #                 detail lines
      # [list_width]    the list pane width; by default a third of the
      #                 window, 20 to 40 columns
      # [bottom_meta]   called with an item, returns the meta line text
      # [actions]       an Array of BBS::Windows::ButtonBar descriptors
      # [on_activate]   called with <tt>(item, window)</tt> on Enter
      # [close_button]  appends a Close button (default true)
      # [close_label]   the Close button's label
      # [empty_message] the detail text when nothing is selected
      # [width]         the window width; by default the screen less 4
      # [height]        the window height; by default the screen less 6
      # [maximizable]   gives the window the zoom gadget
      def initialize(app:, title:, items:, item_label:, render_detail:,
                     list_width: nil, bottom_meta: nil, actions: nil, on_activate: nil,
                     close_button: true, close_label: '&Close',
                     empty_message: '  (empty)',
                     width: nil, height: nil, maximizable: false)
        super(title: title, modal: false, maximizable: maximizable)
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

      # Opens the window on the application, focuses the list, and renders
      # the detail of the selected item.
      #
      # Returns +self+.
      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@list_widget) if @list_widget
        reload_detail
        self
      end

      # Renders the selected item into the detail pane and the meta line, or
      # shows the empty message when nothing is selected. With
      # +keep_scroll+ the detail keeps its scroll position (clamped to the
      # new length); otherwise it scrolls to the top.
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

      # Replaces the list with +items+, selects the first one, and renders its
      # detail. +title+, when given, becomes the window title.
      def replace_items(items, title: nil)
        @items = items
        @list_widget.items    = items
        @list_widget.selected = 0
        @list_widget.scroll   = 0
        self.title = title if title
        reload_detail
      end

      # A master/detail window can be resized; #place lays the panes out
      # again.
      def resizable? = true

      # Returns the un-maximized bounds as <tt>[x, y, width, height]</tt>:
      # the requested size, or the screen less 4 columns and 6 rows,
      # centred.
      def normal_rect
        w = @width  || (@app.cols - 4)
        h = @height || (@app.rows - 6)
        [((@app.cols - w) / 2) + 1, ((@app.rows - h) / 2) + 1, w, h]
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

        return unless @meta_label
        meta_y = bounds.y + h - (has_buttons ? 3 : 2)
        @meta_label.layout(bounds.x + 2, meta_y, bounds.width - 4, 1)
      end
    end
  end
end
