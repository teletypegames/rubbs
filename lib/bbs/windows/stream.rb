# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative 'button_bar'

module BBS
  module Windows
    # A live stream window: scrollable history + single-line input + poll.
    #
    #   BBS::Windows::Stream.open(app,
    #     title: ' Live Chat ',
    #     initial_lines: services[:chat].history.map { |l| fmt(l) },
    #     placeholder: 'Type a message and press Enter…',
    #     on_submit: ->(text, app) {
    #       services[:chat].broadcast(username, text.strip)
    #     },
    #     on_poll: ->(app) {
    #       services[:chat].drain(app.session_id).map { |l| fmt(l) }
    #     }
    #   )
    #
    # <tt>on_submit(text, app)</tt> is called when the user presses Enter on
    # a non-empty input. The input is cleared automatically afterwards unless
    # the handler returns +:keep+.
    #
    # <tt>on_poll(app)</tt> is invoked from the application's idle tick
    # (~1s). It should return an Array of new lines to append (or nil/[]).
    class Stream < Window
      # Creates a stream window with the keywords of Stream.new and opens it
      # on +app+.
      #
      # Returns the Stream window.
      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      # The BBS::Widgets::ScrollView of past lines and the
      # BBS::Widgets::TextInput under it.
      attr_reader :history, :input

      # The options of ::new and their defaults.
      OPTIONS = {
        initial_lines: [],
        placeholder:   '',
        on_submit:     nil,
        on_poll:       nil,
        buffer_size:   500,
        width:         nil,
        height:        nil,
        close_button:  true,
        close_label:   '&Close',
        maximizable:   false
      }.freeze

      # Creates the window and its widgets, centred on +app+'s screen. It is
      # not opened; see #attach.
      #
      # [app]   the BBS::Application
      # [title] the window title
      #
      # The +options+ (OPTIONS):
      #
      # [initial_lines] the lines the history starts with
      # [placeholder]   the text the empty input shows
      # [on_submit]     called with <tt>(text, app)</tt> on Enter
      # [on_poll]       called with +app+ on each tick; returns new lines
      # [buffer_size]   the most lines the history keeps (default 500)
      # [width]         the window width; by default the screen less 8
      # [height]        the window height; by default the screen less 6
      # [close_button]  adds a Close button (default true)
      # [close_label]   the Close button's label
      # [maximizable]   gives the window the zoom gadget
      #
      # Raises ArgumentError for an unknown option.
      def initialize(app:, title:, **options)
        unknown = options.keys - OPTIONS.keys
        raise ArgumentError, "unknown stream options: #{unknown.inspect}" unless unknown.empty?

        @options = OPTIONS.merge(options)
        super(title: title, modal: false, maximizable: @options[:maximizable])
        self.theme = app.theme
        @app = app
        build
      end

      # Opens the window on the application and focuses the input.
      #
      # Returns +self+.
      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@input)
        self
      end

      # Called on the application's idle tick: appends the lines +on_poll+
      # returns to the history, drops the oldest beyond +buffer_size+, and
      # scrolls to the end. Does nothing without +on_poll+ or new lines.
      def tick(_app)
        new_lines = @options[:on_poll]&.call(@app)
        return if new_lines.nil? || new_lines.empty?

        @history.lines = (@history.lines + Array(new_lines)).last(@options[:buffer_size])
        scroll_to_end
      end

      # A stream window can be resized; #place lays it out again.
      def resizable? = true

      # Returns the un-maximized bounds as <tt>[x, y, width, height]</tt>:
      # the requested size, or the screen less 8 columns and 6 rows,
      # centred.
      def normal_rect
        w = @options[:width]  || (@app.cols - 8)
        h = @options[:height] || (@app.rows - 6)
        [((@app.cols - w) / 2) + 1, ((@app.rows - h) / 2) + 1, w, h]
      end

      # History on top, the input line under it, the button row at the
      # bottom; the history stays scrolled to its end.
      def place(x, y, width, height)
        layout(x, y, width, height)
        @history.layout(x + 2, y + 1, width - 4, [height - 4, 1].max)
        scroll_to_end
        @input.layout(x + 2, y + height - 3, width - 4, 1)
        @input.send(:adjust_scroll)
        ButtonBar.place(self, @bar[:widgets], @bar_descriptors) if @bar
      end

      private

      def scroll_to_end = @history.scroll = [@history.lines.size - @history.bounds.height, 0].max

      def build
        @history = Widgets::ScrollView.new(lines: @options[:initial_lines])
        @input   = Widgets::TextInput.new(placeholder: @options[:placeholder])
        @input.on_submit = method(:handle_input_submit)
        add(@history)
        add(@input)
        layout(*normal_rect)
        attach_close_button if @options[:close_button]
        place(*normal_rect)
      end

      def attach_close_button
        @bar_descriptors = [{ label: @options[:close_label], cancel: true }]
        @bar = ButtonBar.attach(self, @app, @bar_descriptors)
      end

      def handle_input_submit(value, _input)
        text = value.to_s
        return :handled if text.strip.empty?

        result = @options[:on_submit]&.call(text, @app)
        @input.value = '' unless result == :keep
        :handled
      end
    end
  end
end
