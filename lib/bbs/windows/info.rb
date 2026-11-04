# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative '../frame_buffer'
require_relative 'button_bar'
require_relative 'info/body'

module BBS
  module Windows
    # A centered window for messages, splash screens, info displays.
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
    # When <tt>scroll: true</tt>, body items are flattened into a single
    # ScrollView filling the inner area. Use this for long, paginated content
    # lists.
    #
    # Body item types:
    #
    # [String]                                 label with the +:window_text+ style
    # [<tt>:spacer</tt>, <tt>''</tt>, +nil+]   blank row
    # [<tt>:rule</tt>]                         horizontal line
    # [<tt>{ text:, style:, align: }</tt>]     styled label
    # [<tt>{ kv: [[k, v], ...], label_width: }</tt>] key/value rows
    # [<tt>{ widget:, height: }</tt>]          arbitrary widget (non-scroll only)
    # [BBS::Widget]                            as-is, its own height or 1 row
    #                                          (non-scroll only)
    #
    # Default buttons: a single centered <tt>[ Close ]</tt> if
    # <tt>buttons:</tt> is nil.
    class Info < Window
      # The button row used when no +buttons+ are given: one Close button.
      DEFAULT_BUTTON  = [{ label: '&Close', cancel: true }].freeze
      # The blank cells around the body: columns on each side, rows above,
      # and rows below the button row.
      DEFAULT_PADDING = { sides: 2, top: 1, bottom: 2 }.freeze

      # The options of ::new and their defaults.
      OPTIONS = {
        body:        [],
        buttons:     nil,
        width:       60,
        height:      nil,
        scroll:      false,
        padding:     nil,
        maximizable: false
      }.freeze
      # The body rows of a scrolling window without a height of its own.
      SCROLL_ROWS = 10

      # Creates an info window with the keywords of Info.new and opens it on
      # +app+.
      #
      # Returns the Info window.
      def self.open(app, **)
        new(app: app, **).tap(&:attach)
      end

      # The BBS::Widgets::ScrollView holding the body in scroll mode; +nil+
      # otherwise.
      attr_reader :scroll_view

      # Creates the window and its widgets, centred on +app+'s screen. It is
      # not opened; see #attach.
      #
      # [app]   the BBS::Application
      # [title] the window title
      #
      # The +options+ (OPTIONS):
      #
      # [body]        an Array of body items (see above)
      # [buttons]     an Array of BBS::Windows::ButtonBar descriptors;
      #               +nil+ gives DEFAULT_BUTTON, <tt>[]</tt> no buttons
      # [width]       the window width (default 60)
      # [height]      the window height; by default it fits the body
      #               (SCROLL_ROWS body rows in scroll mode)
      # [scroll]      puts the body in a scrolling view
      # [padding]     a Hash overriding DEFAULT_PADDING entries
      # [maximizable] gives the window the zoom gadget
      #
      # Raises ArgumentError for an unknown option, and when a widget body
      # item is used in scroll mode.
      def initialize(app:, title:, **options)
        unknown = options.keys - OPTIONS.keys
        raise ArgumentError, "unknown info options: #{unknown.inspect}" unless unknown.empty?

        @options = OPTIONS.merge(options)
        super(title: title, modal: false, maximizable: @options[:maximizable])
        self.theme = app.theme
        @app     = app
        @buttons = @options[:buttons].nil? ? DEFAULT_BUTTON.dup : Array(@options[:buttons])
        @padding = DEFAULT_PADDING.merge(@options[:padding] || {})
        build
      end

      # Opens the window on the application and focuses the primary button,
      # when there is one.
      #
      # Returns +self+.
      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@primary_button) if @primary_button
        self
      end

      # Only the scrolling body can be laid out at another size.
      def resizable? = @options[:scroll]

      # Returns the un-maximized bounds as <tt>[x, y, width, height]</tt>:
      # the requested size (or the fitted height), shrunk to leave a
      # two-cell margin, centred on the screen.
      def normal_rect
        w = [@options[:width], @app.cols - 4].min
        h = [@options[:height] || (body_rows + chrome_rows), @app.rows - 4].min
        [((@app.cols - w) / 2) + 1, ((@app.rows - h) / 2) + 1, w, h]
      end

      # The scroll body fills the new size; its lines were wrapped by the
      # caller, so a wider window shows them as they are.
      def place(x, y, width, height)
        layout(x, y, width, height)
        rows = [height - chrome_rows, 1].max
        @scroll_view.layout(*inside(x, y, width), rows)
        @scroll_view.scroll = @scroll_view.scroll.clamp(0, [@scroll_view.lines.size - rows, 0].max)
        ButtonBar.place(self, @bar[:widgets], @buttons)
      end

      private

      # The rows around the body: the padding and the button row.
      def chrome_rows = @padding[:top] + @padding[:bottom] + (@buttons.any? ? 2 : 0)

      # The body's corner and width in a window at +x+, +y+, +width+ wide.
      def inside(x, y, width) = [x + @padding[:sides], y + @padding[:top], width - (@padding[:sides] * 2)]

      def body_rows = @options[:scroll] ? SCROLL_ROWS : @options[:body].sum { |item| Body.rows(item) }

      def build
        layout(*normal_rect)
        area = inside(bounds.x, bounds.y, bounds.width)
        @options[:scroll] ? scroll_body(*area, [bounds.height - chrome_rows, 0].max) : static_body(*area)
        @bar = ButtonBar.attach(self, @app, @buttons)
        @primary_button = @bar[:primary]
      end

      def scroll_body(x, y, width, height)
        body = Body.new(self)
        @scroll_view = Widgets::ScrollView.new(lines: @options[:body].flat_map { |item| body.lines(item, width) })
        @scroll_view.layout(x, y, width, height)
        add(@scroll_view)
      end

      def static_body(x, y, width)
        body = Body.new(self)
        @options[:body].reduce(y) { |row, item| row + body.place(item, x, row, width) }
      end
    end
  end
end
