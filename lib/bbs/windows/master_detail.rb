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
      # The options of ::new and their defaults.
      OPTIONS = {
        list_width:    nil,
        bottom_meta:   nil,
        actions:       nil,
        on_activate:   nil,
        close_button:  true,
        close_label:   '&Close',
        empty_message: '  (empty)',
        width:         nil,
        height:        nil,
        maximizable:   false
      }.freeze

      # Creates a master/detail window with the keywords of MasterDetail.new
      # and opens it on +app+.
      #
      # Returns the MasterDetail window.
      def self.open(app, **)
        new(app: app, **).tap(&:attach)
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
      #
      # The +options+ (OPTIONS):
      #
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
      #
      # Raises ArgumentError for an unknown option.
      def initialize(app:, title:, items:, item_label:, render_detail:, **options)
        unknown = options.keys - OPTIONS.keys
        raise ArgumentError, "unknown master/detail options: #{unknown.inspect}" unless unknown.empty?

        @options = OPTIONS.merge(options)
        super(title: title, modal: false, maximizable: @options[:maximizable])
        self.theme = app.theme
        @app           = app
        @item_label    = item_label
        @render_detail = render_detail
        @actions       = actions
        build(items)
      end

      # Opens the window on the application, focuses the list, and renders
      # the detail of the selected item.
      #
      # Returns +self+.
      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@list_widget)
        reload_detail
        self
      end

      # Renders the selected item into the detail pane and the meta line, or
      # shows the empty message when nothing is selected. With
      # +keep_scroll+ the detail keeps its scroll position (clamped to the
      # new length); otherwise it scrolls to the top.
      def reload_detail(keep_scroll: false)
        item   = @list_widget.selected_item
        scroll = keep_scroll && item ? @detail_view.scroll : 0
        @detail_view.lines  = detail_lines(item)
        @detail_view.scroll = scroll.clamp(0, [@detail_view.lines.size - @detail_view.bounds.height, 0].max)
        @meta_label&.text = item ? @options[:bottom_meta].call(item) : ''
      end

      # Replaces the list with +items+, selects the first one, and renders its
      # detail. +title+, when given, becomes the window title.
      def replace_items(items, title: nil)
        @list_widget.items    = items
        @list_widget.selected = 0
        @list_widget.scroll   = 0
        self.title = title if title
        reload_detail
      end

      # The selected item of the list, or +nil+.
      def selected = @list_widget.selected_item

      # A master/detail window can be resized; #place lays the panes out
      # again.
      def resizable? = true

      # Returns the un-maximized bounds as <tt>[x, y, width, height]</tt>:
      # the requested size, or the screen less 4 columns and 6 rows,
      # centred.
      def normal_rect
        w = @options[:width]  || (@app.cols - 4)
        h = @options[:height] || (@app.rows - 6)
        [((@app.cols - w) / 2) + 1, ((@app.rows - h) / 2) + 1, w, h]
      end

      # Lays the window out at the given size (terminal resized, maximized,
      # restored) and re-renders the detail at the new pane width.
      def place(x, y, width, height)
        layout(x, y, width, height)
        place_panes
        ButtonBar.place(self, @bar[:widgets], @actions)
        keep_selection_in_sight
        reload_detail(keep_scroll: true)
      end

      private

      def detail_lines(item)
        item.nil? ? [@options[:empty_message]] : Array(@render_detail.call(item, @detail_view.bounds.width - 1))
      end

      def actions
        list = Array(@options[:actions]).dup
        list << { label: @options[:close_label], cancel: true } if @options[:close_button]
        list
      end

      def keep_selection_in_sight
        list = @list_widget
        list.scroll = [list.selected - list.bounds.height + 1, 0].max if list.selected >= list.scroll + list.bounds.height
      end

      def build(items)
        layout(*normal_rect)
        @list_widget = list(items)
        @detail_view = Widgets::ScrollView.new(lines: [])
        @meta_label  = Widgets::Label.new(text: '', style_key: :input_label) if @options[:bottom_meta]
        [@list_widget, @detail_view, @meta_label].compact.each { |w| add(w) }
        @bar = ButtonBar.attach(self, @app, @actions)
        place_panes
      end

      def list(items)
        list = Widgets::ListBox.new(items: items, label: ->(item) { "  #{@item_label.call(item)}".ljust(@list_w || 0) })
        list.on_select = ->(_, _) { reload_detail }
        on_activate = @options[:on_activate]
        list.on_activate = ->(item, _) { on_activate.call(item, self) if item; :handled } if on_activate
        list
      end

      # The rows of the two panes: the window less its frame, the meta line
      # and the button row; at least 3.
      def pane_height
        [bounds.height - 4 - (@meta_label ? 1 : 0) - (@actions.empty? ? 0 : 1), 3].max
      end

      def list_pane_width
        width = @options[:list_width] || [(bounds.width / 3).clamp(20, 40), bounds.width - 10].min
        width.clamp(1, [bounds.width / 2, 1].max)
      end

      def place_panes
        @list_w = list_pane_width
        x = bounds.x + 2
        y = bounds.y + 2
        @list_widget.layout(x, y, @list_w, pane_height)
        @detail_view.layout(x + @list_w + 2, y, [bounds.width - @list_w - 5, 1].max, pane_height)
        place_meta
      end

      # The meta line, over the button row when there is one.
      def place_meta
        @meta_label&.layout(bounds.x + 2, bounds.y + bounds.height - (@actions.empty? ? 2 : 3), bounds.width - 4, 1)
      end
    end
  end
end
