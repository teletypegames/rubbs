# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative 'button_bar'

module BBS
  module Windows
    # A long text to read: its lines in a scroll view (arrows, PgUp/PgDn,
    # Home/End, the wheel), a line under it that says where the reader is,
    # and buttons. Declared as <tt>window :x, :reader</tt> (BBS::WindowSpec).
    #
    #   window :rfc, :reader do
    #     title     { "#{rfc.name}: #{rfc.title}" }
    #     max_width 78
    #     lines     { |width| styled(doc) }
    #     where     { |view| "line #{view.scroll + 1}/#{view.lines.size}" }
    #     action('Contents') { |reader| contents(reader, doc) }
    #   end
    class Reader < Window
      # The options and their defaults: the +lines+ (an Array, or a callable
      # taking the text's width), +where+ (a callable taking the
      # BBS::Widgets::ScrollView, or +nil+ for "line a/b · n%"), the
      # +actions+ (BBS::Windows::ButtonBar descriptors, Close added), the
      # widest the window gets (+max_width+), its size, and +on_key+: keys
      # (as BBS::Telnet#readkey names them) to callables taking the reader
      # and the key, run before the text sees the key.
      OPTIONS = { lines: [], where: nil, actions: [], max_width: nil, width: nil, height: nil,
                  maximizable: true, on_key: {} }.freeze

      # Opens a reader on +app+ with the options of ::new. Returns it.
      def self.open(app, **)
        new(app: app, **).tap(&:attach)
      end

      # The scroll view of the text.
      attr_reader :view

      # Builds the reader titled +title+ on +app+. Raises ArgumentError for
      # an option not in OPTIONS.
      def initialize(app:, title:, **options)
        unknown = options.keys - OPTIONS.keys
        raise ArgumentError, "unknown reader options: #{unknown.inspect}" unless unknown.empty?

        @options = OPTIONS.merge(options)
        super(title: title, modal: false, maximizable: @options[:maximizable])
        self.theme = app.theme
        @app     = app
        @view    = Widgets::ScrollView.new(lines: [])
        @where   = Widgets::Label.new(text: '', style_key: :input_label)
        @buttons = buttons
        build
      end

      # Puts the reader on the application with the text focused. Returns
      # +self+.
      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@view)
        self
      end

      # Readers can be resized and maximized.
      def resizable? = true

      # Moves the text so that line +index+ (0-based) is the second row.
      # Returns +self+.
      def jump(index)
        @view.scroll = (index - 1).clamp(0, max_scroll)
        self
      end

      # Runs the reader's own key (+on_key+) of +event+, then the window's.
      def handle_event(event)
        run = event.key? && @options[:on_key][event.key]
        return super unless run

        run.call(self, event.key)
        :handled
      end

      # Fills the text again from its +lines+ (when they are a callable),
      # keeping the place.
      def reload
        @filled_width = nil
        fill
        self
      end

      # Replaces the text with +lines+ and goes to the top.
      def lines=(lines)
        @options[:lines] = lines
        @filled_width    = nil
        @view.lines      = Array(lines.respond_to?(:call) ? lines.call(@view.bounds.width - 1) : lines)
        @view.scroll = 0
      end

      # As wide as the desktop allows up to +max_width+, as tall as the
      # desktop less a row above and below, unless +width+/+height+ say.
      def normal_rect
        _, dy, dw, dh = @app.desktop_rect
        w = [@options[:width] || (dw - 2), @options[:max_width] || dw].min
        h = [@options[:height] || (dh - 2), MIN_HEIGHT].max
        [((dw - w) / 2) + 1, dy + 1, w, h]
      end

      # Lays the text, the position line and the buttons out in the window.
      def place(x, y, width, height)
        layout(x, y, width, height)
        place_widgets(x, y, width, height)
        fill
        @view.scroll = @view.scroll.clamp(0, max_scroll)
      end

      # Draws the reader with its position line up to date.
      def render(frame)
        @where.text = where
        super
      end

      private

      def buttons
        actions = Array(@options[:actions]).map { |a| a.merge(keep_open: true, align: a[:align] || :left) }
        [*actions, { label: '&Close', cancel: true }]
      end

      def build
        add(@view)
        add(@where)
        layout(*normal_rect)
        @bar = ButtonBar.attach(self, @app, @buttons)
        place(*normal_rect)
      end

      def place_widgets(x, y, width, height)
        @view.layout(x + 2, y + 1, [width - 3, 1].max, [height - 4, 1].max)
        @where.layout(x + 2, y + height - 3, [width - 4, 1].max, 1)
        ButtonBar.place(self, @bar[:widgets], @buttons)
      end

      def fill
        source = @options[:lines]
        return @view.lines = Array(source) unless source.respond_to?(:call)

        width = @view.bounds.width - 1
        return if @filled_width == width

        @filled_width = width
        @view.lines   = Array(source.call(width))
      end

      def max_scroll = [@view.lines.size - @view.bounds.height, 0].max

      def where
        return @options[:where].call(@view) if @options[:where]

        size = [@view.lines.size, 1].max
        last = [@view.scroll + @view.bounds.height, @view.lines.size].min
        "line #{last}/#{@view.lines.size} · #{100 * last / size}%"
      end
    end
  end
end
