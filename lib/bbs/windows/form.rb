# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative 'button_bar'

module BBS
  module Windows
    # A form dialog with labeled input rows, optional textarea, and a status
    # line for inline validation feedback.
    #
    #   BBS::Windows::Form.open(app,
    #     title: " Profile — #{u} ", width: 64,
    #     fields: [
    #       { key: :signature, label: 'Signature', value: '...' },
    #       { key: :location,  label: 'Location',  value: '...' },
    #       { key: :notes,     label: 'Notes',     value: '...' },
    #     ],
    #     on_submit: ->(values, form) {
    #       service.update(values); :close
    #     }
    #   )
    #
    # Field descriptor:
    #   { key:, label:, value:, type:, max_length:, placeholder:, password:, rows: }
    #
    # Field types:
    #   :input    (default) — single-line TextInput; label on left.
    #   :textarea           — multi-line TextArea; full width, label ignored.
    #   :checkbox           — Checkbox; label is part of the widget.
    #
    # on_submit receives `(values_hash, self)`. Return :keep to keep the
    # window open (e.g., after `form.error('...')`); any other value closes.
    #
    # `hint:` shows an info line above the fields (no label/value, no input).
    class Form < Window
      DEFAULT_PADDING = { sides: 2, top: 1, bottom: 2 }.freeze

      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      attr_reader :status_label

      def initialize(app:, title:, fields:, on_submit:,
                     hint: nil, width: 60, height: nil,
                     submit_label: '&Save', cancel_label: '&Cancel',
                     padding: nil, on_cancel: nil)
        super(title: title, modal: true)
        self.theme = app.theme
        @app          = app
        @fields       = fields
        @hint         = hint
        @on_submit    = on_submit
        @on_cancel    = on_cancel
        @submit_label = submit_label
        @cancel_label = cancel_label
        @width        = width
        @height       = height
        @padding      = DEFAULT_PADDING.merge(padding || {})
        @widgets      = {}
        build
      end

      def attach
        @app.open_window(self)
        reset_focus
        first = @fields.first
        focus_manager.focus(@widgets[first[:key]]) if first && @widgets[first[:key]]
        self
      end

      def values
        @fields.each_with_object({}) { |f, h| h[f[:key]] = field_value(f) }
      end

      def error(text)
        return unless @status_label
        @status_label.text      = text.to_s
        @status_label.style_key = :error
      end

      def info(text)
        return unless @status_label
        @status_label.text      = text.to_s
        @status_label.style_key = :input_label
      end

      def clear_status
        @status_label&.text = ''
      end

      private

      def field_value(field)
        widget = @widgets[field[:key]]
        return nil unless widget
        return widget.checked if field[:type] == :checkbox
        widget.value
      end

      def build
        w = [@width, @app.cols - 4].min
        heights = @fields.map { |f| natural_field_height(f) }

        hint_block   = @hint ? 2 : 0           # hint + spacer
        spacing      = [@fields.length - 1, 0].max
        status_block = 1
        buttons_block = 2                       # spacer + button row

        h_auto = @padding[:top] + hint_block + heights.sum + spacing +
                 1 + status_block + buttons_block + @padding[:bottom]
        h = @height || h_auto
        h = [h, @app.rows - 4].min

        # If explicit height + exactly one textarea without :rows, expand it.
        if @height
          ta_indices = @fields.each_index.select do |i|
            @fields[i][:type] == :textarea && !@fields[i][:rows]
          end
          if ta_indices.length == 1
            idx        = ta_indices.first
            fixed_rest = heights.each_with_index.reject { |_, i| i == idx }.sum { |row, _| row }
            available  = h - @padding[:top] - @padding[:bottom] - hint_block -
                         spacing - 1 - status_block - buttons_block
            heights[idx] = [available - fixed_rest, 1].max
          end
        end

        x = (@app.cols - w) / 2 + 1
        y = (@app.rows - h) / 2 + 1
        layout(x, y, w, h)

        inner_x = bounds.x + @padding[:sides]
        inner_w = w - @padding[:sides] * 2
        row_y   = bounds.y + @padding[:top]

        if @hint
          hint = BBS::Widgets::Label.new(text: @hint, style_key: :input_label)
          hint.layout(inner_x, row_y, inner_w, 1)
          add(hint)
          row_y += 2
        end

        label_w = compute_label_width

        @fields.each_with_index do |f, i|
          place_field(f, heights[i], inner_x, inner_w, row_y, label_w)
          row_y += heights[i] + 1
        end

        @status_label = BBS::Widgets::Label.new(text: '', style_key: :error)
        @status_label.layout(inner_x, bounds.y + h - 3, inner_w, 1)
        add(@status_label)

        ButtonBar.attach(self, @app, [
          { key: :submit, label: @submit_label, primary: true,
            on_click:  ->(_w) { @on_submit ? @on_submit.call(values, self) : :close } },
          { key: :cancel, label: @cancel_label, cancel: true,
            on_click:  ->(_w) { @on_cancel&.call(self) } }
        ])
      end

      def natural_field_height(field)
        case field[:type]
        when :textarea then field[:rows] || 6
        else 1
        end
      end

      def compute_label_width
        with_labels = @fields.select { |f| f[:label] && f[:type] != :textarea && f[:type] != :checkbox }
        return 0 if with_labels.empty?
        max = with_labels.map { |f| f[:label].to_s.length }.max
        [max + 1, 16].min.clamp(8, 16)
      end

      def place_field(field, height, inner_x, inner_w, y, label_w)
        case field[:type]
        when :textarea
          widget = BBS::Widgets::TextArea.new(
            value: field[:value].to_s,
            max_length: field[:max_length] || 8_000
          )
          widget.layout(inner_x, y, inner_w, height)
        when :checkbox
          widget = BBS::Widgets::Checkbox.new(
            label: field[:label].to_s,
            checked: field[:value] ? true : false
          )
          widget.layout(inner_x, y, inner_w, 1)
        else
          if field[:label]
            label = BBS::Widgets::Label.new(text: field[:label].to_s, style_key: :input_label)
            label.layout(inner_x, y, label_w, 1)
            add(label)
            input_x = inner_x + label_w + 2
            input_w = inner_w - label_w - 2
          else
            input_x = inner_x
            input_w = inner_w
          end
          widget = BBS::Widgets::TextInput.new(
            value: field[:value].to_s,
            placeholder: field[:placeholder].to_s,
            max_length: field[:max_length] || 256,
            password: field[:password] ? true : false
          )
          widget.layout(input_x, y, input_w, 1)
        end
        add(widget)
        @widgets[field[:key]] = widget
      end
    end
  end
end
