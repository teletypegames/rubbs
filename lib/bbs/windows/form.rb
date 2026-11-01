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
    # A field descriptor is a Hash:
    #
    # [key]         the key of the field's value in #values
    # [label]       the text left of an input, or the checkbox's text
    # [value]       the starting value (true/false for a checkbox)
    # [type]        +:input+, +:textarea+ or +:checkbox+
    # [max_length]  the longest value accepted (256 for an input, 8000 for a
    #               textarea)
    # [placeholder] the text an empty input shows
    # [password]    masks an input's text
    # [rows]        a textarea's height (default 6)
    #
    # Field types:
    #
    # [:input]    (default) single-line TextInput; label on the left
    # [:textarea] multi-line TextArea; full width, label ignored
    # [:checkbox] Checkbox; the label is part of the widget
    #
    # on_submit receives <tt>(values_hash, self)</tt>. Return +:keep+ to keep
    # the window open (e.g. after <tt>form.error('...')</tt>); any other value
    # closes.
    #
    # <tt>hint:</tt> shows an info line above the fields (no label/value, no
    # input).
    class Form < Window
      # The blank cells around the fields: columns on each side, rows above,
      # and rows below the button row.
      DEFAULT_PADDING = { sides: 2, top: 1, bottom: 2 }.freeze

      # Creates a form with the keywords of Form.new and opens it on +app+.
      #
      # Returns the Form.
      def self.open(app, **kw)
        new(app: app, **kw).tap(&:attach)
      end

      # The BBS::Widgets::Label above the buttons used by #error and #info.
      attr_reader :status_label

      # Creates the form window and its widgets, sized to fit the fields and
      # centred on +app+'s screen. It is not opened; see #attach.
      #
      # [app]          the BBS::Application
      # [title]        the window title
      # [fields]       an Array of field descriptors
      # [on_submit]    called with <tt>(values, form)</tt> by the submit
      #                button; +nil+ just closes the window
      # [hint]         an info line above the fields
      # [width]        the window width (default 60)
      # [height]       the window height; by default it fits the fields
      # [submit_label] the submit button's label (+&+ marks the hotkey)
      # [cancel_label] the cancel button's label
      # [padding]      a Hash overriding DEFAULT_PADDING entries
      # [on_cancel]    called with the form when cancel is pressed
      # [maximizable]  gives the window the zoom gadget
      def initialize(app:, title:, fields:, on_submit:,
                     hint: nil, width: 60, height: nil,
                     submit_label: '&Save', cancel_label: '&Cancel',
                     padding: nil, on_cancel: nil, maximizable: false)
        super(title: title, modal: false, maximizable: maximizable)
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

      # Opens the window on the application and focuses the first field.
      #
      # Returns +self+.
      def attach
        @app.open_window(self)
        reset_focus
        first = @fields.first
        focus_manager.focus(@widgets[first[:key]]) if first && @widgets[first[:key]]
        self
      end

      # Returns a Hash of field key to the current value: a String for an
      # input or textarea, true or false for a checkbox.
      def values
        @fields.each_with_object({}) { |f, h| h[f[:key]] = field_value(f) }
      end

      # Shows +text+ on the status line in the error style.
      def error(text)
        return unless @status_label
        @status_label.text      = text.to_s
        @status_label.style_key = :error
      end

      # Shows +text+ on the status line in the label style.
      def info(text)
        return unless @status_label
        @status_label.text      = text.to_s
        @status_label.style_key = :input_label
      end

      # Empties the status line.
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
        @labels = {}
        @fields.each { |f| create_field(f) }
        @hint_label   = BBS::Widgets::Label.new(text: @hint, style_key: :input_label) if @hint
        @status_label = BBS::Widgets::Label.new(text: '', style_key: :error)
        add(@hint_label) if @hint_label
        add(@status_label)

        @bar_descriptors = [
          { key: :submit, label: @submit_label, primary: true,
            on_click:  ->(_w) { @on_submit ? @on_submit.call(values, self) : :close } },
          { key: :cancel, label: @cancel_label, cancel: true,
            on_click:  ->(_w) { @on_cancel&.call(self) } }
        ]
        layout(*normal_rect)
        @bar = ButtonBar.attach(self, @app, @bar_descriptors)
        place(*normal_rect)
      end

      public

      # A form can be resized; #place lays the fields out again.
      def resizable? = true

      # Returns the un-maximized bounds as <tt>[x, y, width, height]</tt>:
      # the requested size (or the fitted height), shrunk to leave a
      # two-cell margin, centred on the screen.
      def normal_rect
        w = [@width, @app.cols - 4].min
        h = [@height || natural_height, @app.rows - 4].min
        [((@app.cols - w) / 2) + 1, ((@app.rows - h) / 2) + 1, w, h]
      end

      # Fields one under the other at the given size; a single textarea
      # without its own :rows takes the height left over (always when the
      # form has an explicit height or is maximized).
      def place(x, y, width, height)
        layout(x, y, width, height)
        heights = @fields.map { |f| natural_field_height(f) }
        grow = @fields.each_index.select { |i| @fields[i][:type] == :textarea && !@fields[i][:rows] }
        if grow.length == 1 && (@height || maximized?)
          rest = heights.each_with_index.reject { |_, i| i == grow.first }.sum(&:first)
          heights[grow.first] = [height - fixed_rows - rest, 1].max
        end

        inner_x = x + @padding[:sides]
        inner_w = width - (@padding[:sides] * 2)
        row_y   = y + @padding[:top]
        if @hint_label
          @hint_label.layout(inner_x, row_y, inner_w, 1)
          row_y += 2
        end

        label_w = compute_label_width
        @fields.each_with_index do |f, i|
          place_field(f, heights[i], inner_x, inner_w, row_y, label_w)
          row_y += heights[i] + 1
        end

        @status_label.layout(inner_x, y + height - 3, inner_w, 1)
        ButtonBar.place(self, @bar[:widgets], @bar_descriptors) if @bar
      end

      private

      # Rows of a form that are not field rows: padding, hint, the gaps
      # between fields, the status line and the button row.
      def fixed_rows
        @padding[:top] + (@hint ? 2 : 0) + [@fields.length - 1, 0].max + 1 + 1 + 2 + @padding[:bottom]
      end

      def natural_height
        fixed_rows + @fields.sum { |f| natural_field_height(f) }
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

      def create_field(field)
        widget = case field[:type]
                 when :textarea
                   BBS::Widgets::TextArea.new(value: field[:value].to_s, max_length: field[:max_length] || 8_000)
                 when :checkbox
                   BBS::Widgets::Checkbox.new(label: field[:label].to_s, checked: field[:value] ? true : false)
                 else
                   if field[:label]
                     @labels[field[:key]] = BBS::Widgets::Label.new(text: field[:label].to_s, style_key: :input_label)
                     add(@labels[field[:key]])
                   end
                   BBS::Widgets::TextInput.new(
                     value: field[:value].to_s,
                     placeholder: field[:placeholder].to_s,
                     max_length: field[:max_length] || 256,
                     password: field[:password] ? true : false
                   )
                 end
        add(widget)
        @widgets[field[:key]] = widget
      end

      def place_field(field, height, inner_x, inner_w, y, label_w)
        widget = @widgets[field[:key]]
        case field[:type]
        when :textarea
          widget.layout(inner_x, y, inner_w, height)
          widget.send(:ensure_visible) if widget.respond_to?(:ensure_visible, true)
        when :checkbox
          widget.layout(inner_x, y, inner_w, 1)
        else
          if (label = @labels[field[:key]])
            label.layout(inner_x, y, label_w, 1)
            widget.layout(inner_x + label_w + 2, y, inner_w - label_w - 2, 1)
          else
            widget.layout(inner_x, y, inner_w, 1)
          end
          widget.send(:adjust_scroll)
        end
      end
    end
  end
end
