# frozen_string_literal: true

module Rubbs
  module Modern
    module Windows
      class Form < Window
        # One field of a Form, made from its descriptor: the widget that holds
        # the value, its height and where it goes. ::for picks the kind.
        class Field
          # The field's key in Form#values, and the widget holding its value.
          attr_reader :key, :widget

          # The field for +descriptor+: a TextAreaField, a CheckboxField or,
          # by default, an InputField.
          def self.for(descriptor)
            { textarea: TextAreaField, checkbox: CheckboxField }.fetch(descriptor[:type], InputField).new(descriptor)
          end

          # Builds the field's widgets from +descriptor+.
          def initialize(descriptor)
            @descriptor = descriptor
            @key        = descriptor[:key]
            @widget     = build
          end

          # The widgets the form adds for the field, in order.
          def widgets = [@widget]

          # The rows the field takes at its natural size.
          def height = 1

          # Whether the field takes the rows a form has to spare.
          def grows? = false

          # Whether the field has a label left of it (see Form label width).
          def labelled? = false

          # The field's value.
          def value = @widget.value

          # Lays the field out from column +x+, +width+ wide, on row +y+,
          # +rows+ high, its input +label_width+ columns right of a label.
          def place(x, width, y, _rows, _label_width) = @widget.layout(x, y, width, 1)
        end

        # A single-line Rubbs::Modern::Widgets::TextInput with its label on the left.
        class InputField < Field
          # The label widget and the input, in order.
          def widgets = [@label, @widget].compact

          # Whether the descriptor has a label.
          def labelled? = !@descriptor[:label].nil?

          # Lays the label and the input out on row +y+.
          def place(x, width, y, _rows, label_width)
            if @label
              @label.layout(x, y, label_width, 1)
              @widget.layout(x + label_width + 2, y, width - label_width - 2, 1)
            else
              super
            end
            @widget.send(:adjust_scroll)
          end

          private

          def build
            d = @descriptor
            @label = Widgets::Label.new(text: d[:label].to_s, style_key: :input_label) if d[:label]
            Widgets::TextInput.new(
              value:       d[:value].to_s,
              placeholder: d[:placeholder].to_s,
              max_length:  d[:max_length] || 256,
              password:    d[:password] ? true : false
            )
          end
        end

        # A multi-line Rubbs::Modern::Widgets::TextArea, the form's full width.
        class TextAreaField < Field
          # Its +rows+, 6 by default.
          def height = @descriptor[:rows] || 6

          # True without its own +rows+.
          def grows? = !@descriptor[:rows]

          # Lays the text area out +rows+ high, its cursor kept in sight.
          def place(x, width, y, rows, _label_width)
            @widget.layout(x, y, width, rows)
            @widget.send(:ensure_visible)
          end

          private

          def build = Widgets::TextArea.new(value: @descriptor[:value].to_s, max_length: @descriptor[:max_length] || 8_000)
        end

        # A Rubbs::Modern::Widgets::Checkbox, its label part of the widget.
        class CheckboxField < Field
          # Whether it is checked.
          def value = @widget.checked

          private

          def build = Widgets::Checkbox.new(label: @descriptor[:label].to_s, checked: @descriptor[:value] ? true : false)
        end
      end
    end
  end
end
