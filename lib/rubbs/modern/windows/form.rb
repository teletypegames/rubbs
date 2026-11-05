# frozen_string_literal: true

require_relative '../window'
require_relative '../widgets'
require_relative 'button_bar'
require_relative 'form/fields'

module Rubbs
  module Modern
    module Windows
      # A form dialog with labeled input rows, optional textarea, and a status
      # line for inline validation feedback.
      #
      #   Rubbs::Modern::Windows::Form.open(app,
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
        # The options of ::new and their defaults.
        OPTIONS = {
          on_submit:    nil,
          hint:         nil,
          width:        60,
          height:       nil,
          submit_label: '&Save',
          cancel_label: '&Cancel',
          padding:      nil,
          on_cancel:    nil,
          maximizable:  false
        }.freeze
        # The rows that are not field rows besides the padding, the hint and
        # the gaps between fields: the status line, its gap and the button row.
        CHROME_ROWS = 4

        # Creates a form with the keywords of Form.new and opens it on +app+.
        #
        # Returns the Form.
        def self.open(app, **)
          new(app: app, **).tap(&:attach)
        end

        # The Rubbs::Modern::Widgets::Label above the buttons used by #error and #info.
        attr_reader :status_label

        # Creates the form window and its widgets, sized to fit the fields and
        # centred on +app+'s screen. It is not opened; see #attach.
        #
        # [app]     the Rubbs::Modern::Application
        # [title]   the window title
        # [fields]  an Array of field descriptors
        #
        # The +options+ (OPTIONS):
        #
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
        #
        # Raises ArgumentError for an unknown option.
        def initialize(app:, title:, fields:, **options)
          unknown = options.keys - OPTIONS.keys
          raise ArgumentError, "unknown form options: #{unknown.inspect}" unless unknown.empty?

          @options = OPTIONS.merge(options)
          super(title: title, modal: false, maximizable: @options[:maximizable])
          self.theme = app.theme
          @app     = app
          @fields  = fields.map { |d| Field.for(d) }
          @padding = DEFAULT_PADDING.merge(@options[:padding] || {})
          build
        end

        # Opens the window on the application and focuses the first field.
        #
        # Returns +self+.
        def attach
          @app.open_window(self)
          reset_focus
          focus_manager.focus(@fields.first.widget) unless @fields.empty?
          self
        end

        # Returns a Hash of field key to the current value: a String for an
        # input or textarea, true or false for a checkbox.
        def values = @fields.to_h { |f| [f.key, f.value] }

        # Shows +text+ on the status line in the error style.
        def error(text) = status(text, :error)

        # Shows +text+ on the status line in the label style.
        def info(text) = status(text, :input_label)

        # A form can be resized; #place lays the fields out again.
        def resizable? = true

        # Returns the un-maximized bounds as <tt>[x, y, width, height]</tt>:
        # the requested size (or the fitted height), shrunk to leave a
        # two-cell margin, centred on the screen.
        def normal_rect
          w = [@options[:width], @app.cols - 4].min
          h = [@options[:height] || natural_height, @app.rows - 4].min
          [((@app.cols - w) / 2) + 1, ((@app.rows - h) / 2) + 1, w, h]
        end

        # Fields one under the other at the given size; a single textarea
        # without its own :rows takes the height left over (always when the
        # form has an explicit height or is maximized).
        def place(x, y, width, height)
          layout(x, y, width, height)
          left  = x + @padding[:sides]
          inner = width - (@padding[:sides] * 2)
          row = place_hint(left, inner, y + @padding[:top])
          place_fields(left, inner, row, field_heights(height))
          @status_label.layout(left, y + height - 3, inner, 1)
          ButtonBar.place(self, @bar[:widgets], @bar_descriptors) if @bar
        end

        private

        def status(text, style)
          @status_label.text      = text.to_s
          @status_label.style_key = style
        end

        def build
          @fields.each { |f| f.widgets.each { |w| add(w) } }
          @hint_label = Widgets::Label.new(text: @options[:hint], style_key: :input_label) if @options[:hint]
          @status_label = Widgets::Label.new(text: '', style_key: :error)
          [@hint_label, @status_label].compact.each { |w| add(w) }
          @bar_descriptors = buttons
          layout(*normal_rect)
          @bar = ButtonBar.attach(self, @app, @bar_descriptors)
          place(*normal_rect)
        end

        def buttons
          on_submit, on_cancel = @options.values_at(:on_submit, :on_cancel)
          [{
            key:      :submit,
            label:    @options[:submit_label],
            primary:  true,
            on_click: ->(_w) { on_submit ? on_submit.call(values, self) : :close }
          },
           { key: :cancel, label: @options[:cancel_label], cancel: true, on_click: ->(_w) { on_cancel&.call(self) } }]
        end

        # Lays the hint out on row +y+, when there is one. Returns the row
        # the fields start on.
        def place_hint(x, width, y)
          return y unless @hint_label

          @hint_label.layout(x, y, width, 1)
          y + 2
        end

        def place_fields(x, width, y, heights)
          label_width = self.label_width
          @fields.zip(heights).each do |field, rows|
            field.place(x, width, y, rows, label_width)
            y += rows + 1
          end
        end

        # The rows of each field at a form +height+ high: their natural
        # heights, but a single growing textarea takes what is left over when
        # the form has a height of its own or is maximized.
        def field_heights(height)
          heights = @fields.map(&:height)
          grow    = @fields.each_index.select { |i| @fields[i].grows? }
          return heights unless grow.one? && (@options[:height] || maximized?)

          heights[grow.first] = [height - fixed_rows - (heights.sum - heights[grow.first]), 1].max
          heights
        end

        # Rows of a form that are not field rows: padding, hint, the gaps
        # between fields, the status line and the button row.
        def fixed_rows
          @padding[:top] + (@options[:hint] ? 2 : 0) + [@fields.length - 1, 0].max + CHROME_ROWS + @padding[:bottom]
        end

        def natural_height = fixed_rows + @fields.sum(&:height)

        def label_width
          widths = @fields.select(&:labelled?).map { |f| f.widgets.first.text.to_s.length }
          widths.empty? ? 0 : (widths.max + 1).clamp(8, 16)
        end
      end
    end
  end
end
