# frozen_string_literal: true

module Rubbs
  module Modern
    class WindowSpec
      # The options of a +:reader+ window (Rubbs::Modern::Windows::Reader): its lines,
      # its where-line, its buttons and its own keys, each run in the
      # Rubbs::Modern::WindowContext.
      module ReaderOptions
        private

        def reader_options(context)
          {
            lines:     reader_lines(context),
            max_width: resolve(:max_width, context),
            where:     (->(view) { context.instance_exec(view, &@attrs[:where]).to_s } if @attrs[:where]),
            actions:   @actions.map { |a| reader_action(a, context) },
            on_key:    reader_keys(context)
          }
        end

        def reader_keys(context)
          keys = @attrs[:on_key] || {}
          keys.transform_values { |run| ->(reader, key) { context.instance_exec(reader, key, &run) } }
        end

        def reader_lines(context)
          value = @attrs[:lines]
          value.is_a?(Proc) ? ->(width) { Array(context.instance_exec(width, &value)) } : Array(value)
        end

        def reader_action(action, context)
          run = action[:run]
          action.except(:run).merge(on_click: lambda do |window|
            context.instance_exec(window, &run) if run
            :keep
          end)
        end
      end
    end
  end
end
