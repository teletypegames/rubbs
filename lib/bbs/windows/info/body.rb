# frozen_string_literal: true

module BBS
  module Windows
    class Info < Window
      # The body items of an Info window: how many rows each takes, the
      # lines it gives a scrolling body, and the widgets it places in a
      # static one. Each item is of a kind (::kind), and each kind has a
      # method for each of the two.
      class Body
        # The kinds of the items that are a Symbol, an empty String or +nil+.
        PLAIN_KINDS = { :spacer => :blank, '' => :blank, nil => :blank, :rule => :rule }.freeze
        # The kinds of a Hash item, in the order they are looked for.
        HASH_KINDS = %i[kv widget text].freeze

        # The kind of +item+: +:blank+, +:rule+, +:line+ (a String), +:kv+,
        # +:widget+, +:text+, +:raw_widget+ (a BBS::Widget) or +:other+.
        def self.kind(item)
          return PLAIN_KINDS[item] if PLAIN_KINDS.key?(item)

          case item
          when String then :line
          when Hash then HASH_KINDS.find { |k| item[k] } || :other
          when Widget then :raw_widget
          else :other
          end
        end

        # The rows +item+ takes in a static body.
        def self.rows(item)
          case kind(item)
          when :kv then item[:kv].length
          when :widget then item[:height] || 1
          when :raw_widget then height_of(item)
          else 1
          end
        end

        # The height of +widget+, or 1 before it has one.
        def self.height_of(widget) = widget.bounds.height.positive? ? widget.bounds.height : 1

        # The width of the key column of +pairs+.
        def self.key_width(item) = item[:label_width] || ((item[:kv].map { |k, _| k.to_s.length }.max || 0) + 1).clamp(8, 16)

        # A body for +window+, drawn with its theme and filled with
        # widgets added to it.
        def initialize(window)
          @window = window
        end

        # The lines of +item+ in a scrolling body +width+ wide. Raises
        # ArgumentError for a widget item.
        def lines(item, width) = send(:"lines_#{Body.kind(item)}", item, width)

        # Places the widgets of +item+ at +x+, +y+, +width+ wide in a static
        # body. Returns the rows it took.
        def place(item, x, y, width) = send(:"place_#{Body.kind(item)}", item, x, y, width)

        private

        def theme = @window.theme

        def base = theme[:text]

        def lines_blank(_item, _width) = ['']

        def lines_rule(_item, width) = ["#{theme[:label]}#{'─' * width}#{base}"]

        def lines_line(item, _width) = [item]

        def lines_kv(item, _width)
          width = Body.key_width(item)
          item[:kv].map { |k, v| "#{theme[:input_label]}#{k.to_s.ljust(width)}#{base}  #{v}" }
        end

        def lines_widget(item, width) = item[:text] ? lines_text(item, width) : []

        def lines_text(item, _width) = ["#{item[:style] ? theme[item[:style]] : base}#{item[:text]}#{base}"]

        def lines_raw_widget(_item, _width) = raise(ArgumentError, 'scroll mode does not support widget body items')

        def lines_other(_item, _width) = []

        def place_blank(*) = 1

        alias place_other place_blank

        def place_rule(_item, x, y, width) = label('─' * width, :label, x, y, width)

        def place_line(item, x, y, width) = label(item, :window_text, x, y, width)

        def place_text(item, x, y, width)
          label(item[:text], item[:style] || :window_text, x, y, width, align: item[:align] || :left)
        end

        def place_kv(item, x, y, width)
          key_width = Body.key_width(item)
          item[:kv].each_with_index do |(k, v), i|
            label(k.to_s.ljust(key_width), :input_label, x, y + i, key_width)
            label(v.to_s, :window_text, x + key_width + 2, y + i, width - key_width - 2)
          end
          item[:kv].length
        end

        def place_widget(item, x, y, width) = widget(item[:widget], item[:height], x, y, width)

        def place_raw_widget(item, x, y, width) = widget(item, nil, x, y, width)

        def widget(widget, height, x, y, width)
          height ||= Body.height_of(widget)
          widget.layout(x, y, width, height)
          @window.add(widget)
          height
        end

        # Adds a label of +text+ in +style+ at +x+, +y+, +width+ wide.
        # Returns its one row.
        def label(text, style, x, y, width, align: :left)
          widget(Widgets::Label.new(text: text, style_key: style, align: align), 1, x, y, width)
        end
      end

      private_constant :Body
    end
  end
end
