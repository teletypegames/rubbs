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
    # `on_submit(text, app)` is called when the user presses Enter on a
    # non-empty input. The input is cleared automatically afterwards unless
    # the handler returns `:keep`.
    #
    # `on_poll(app)` is invoked from the application's idle tick (~1s). It
    # should return an Array of new lines to append (or nil/[]).
    class Stream < Window
      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      attr_reader :history, :input

      def initialize(app:, title:, initial_lines: [], placeholder: '',
                     on_submit: nil, on_poll: nil, buffer_size: 500,
                     width: nil, height: nil,
                     close_button: true, close_label: '&Close')
        super(title: title, modal: true)
        self.theme = app.theme
        @app           = app
        @initial_lines = initial_lines
        @placeholder   = placeholder
        @on_submit     = on_submit
        @on_poll       = on_poll
        @buffer_size   = buffer_size
        @width         = width
        @height        = height
        @close_button  = close_button
        @close_label   = close_label
        build
      end

      def attach
        @app.open_window(self)
        reset_focus
        focus_manager.focus(@input)
        self
      end

      def tick(_app)
        return unless @on_poll
        new_lines = @on_poll.call(@app)
        return if new_lines.nil? || new_lines.empty?
        @history.lines  = (@history.lines + Array(new_lines)).last(@buffer_size)
        @history.scroll = [@history.lines.size - @history.bounds.height, 0].max
      end

      private

      def build
        w = @width  || @app.cols - 8
        h = @height || @app.rows - 6
        x = (@app.cols - w) / 2 + 1
        y = (@app.rows - h) / 2 + 1
        layout(x, y, w, h)

        inner_x = bounds.x + 2
        inner_w = bounds.width - 4

        @history = BBS::Widgets::ScrollView.new(lines: @initial_lines)
        @history.layout(inner_x, bounds.y + 1, inner_w, h - 4)
        @history.scroll = [@history.lines.size - @history.bounds.height, 0].max
        add(@history)

        @input = BBS::Widgets::TextInput.new(placeholder: @placeholder)
        @input.on_submit = method(:handle_input_submit)
        @input.layout(inner_x, bounds.y + h - 3, inner_w, 1)
        add(@input)

        if @close_button
          ButtonBar.attach(self, @app, [{ label: @close_label, cancel: true }])
        end
      end

      def handle_input_submit(value, _input)
        text = value.to_s
        return :handled if text.strip.empty?
        result = @on_submit&.call(text, @app)
        @input.value = '' unless result == :keep
        :handled
      end
    end
  end
end
