# frozen_string_literal: true

module BBS
  class WindowSpec
    # How a WindowSpec turns its attributes into the options of its window
    # class: each value resolved and each callback wrapped to run in the
    # BBS::WindowContext.
    module Options
      private

      def options(context)
        send(:"#{@type}_options", context).merge(
          title:  resolve(:title, context).to_s,
          width:  size(:width, context, context.cols),
          height: size(:height, context, context.rows)
        ).compact
      end

      def info_options(context)
        {
          body:    Array(resolve(:body, context)),
          scroll:  resolve(:scroll, context),
          padding: resolve(:padding, context),
          buttons: @buttons&.map { |b| button_descriptor(b, context) }
        }
      end

      def form_options(context)
        {
          fields:       resolve_fields(context),
          hint:         resolve(:hint, context),
          submit_label: resolve(:submit_label, context),
          cancel_label: resolve(:cancel_label, context),
          on_submit:    submit_callback(context),
          on_cancel:    (->(_form) { context.instance_exec(&@attrs[:on_cancel]) } if @attrs[:on_cancel])
        }
      end

      def master_detail_options(context)
        {
          items:         Array(resolve(:items, context)),
          item_label:    label_callback(context),
          render_detail: detail_callback(context),
          list_width:    resolved_list_width(context),
          actions:       @actions.empty? ? nil : @actions.map { |a| action_descriptor(a, context) },
          empty_message: resolve(:empty, context),
          close_button:  resolve(:close_button, context),
          close_label:   resolve(:close_label, context),
          **item_callbacks(context)
        }
      end

      def item_callbacks(context)
        meta, pick = @attrs.values_at(:meta, :on_pick)
        {
          bottom_meta: (meta_callback(meta, context) if meta),
          on_activate: (->(item, _window) { context.instance_exec(item, &pick) } if pick)
        }
      end

      def meta_callback(meta, context)
        meta.is_a?(Proc) ? ->(item) { context.instance_exec(item, &meta).to_s } : ->(_item) { meta.to_s }
      end

      def stream_options(context)
        {
          initial_lines: Array(resolve(:lines, context)),
          placeholder:   resolve(:placeholder, context),
          buffer_size:   resolve(:buffer_size, context),
          on_submit:     stream_submit(context),
          on_poll:       (->(_app) { context.instance_exec(&@attrs[:on_poll]) } if @attrs[:on_poll]),
          close_button:  resolve(:close_button, context),
          close_label:   resolve(:close_label, context)
        }
      end

      def stream_submit(context)
        submit = @attrs[:on_submit]
        return nil unless submit

        lambda do |text, _app|
          context.kept = false
          context.instance_exec(text, &submit)
          context.kept ? :keep : nil
        end
      end

      def label_callback(context)
        label = @attrs[:label]
        case label
        when nil    then lambda(&:to_s)
        when Symbol then ->(item) { item.public_send(label).to_s }
        else ->(item) { context.instance_exec(item, &label).to_s }
        end
      end

      def detail_callback(context)
        detail = @attrs[:detail]
        return ->(_item, _width) { [] } unless detail

        lambda do |item, width|
          Array(context.instance_exec(item, width, &detail)).flat_map { |line| fit(line.to_s, width) }
        end
      end

      def fit(line, width)
        line.empty? ? [''] : FrameBuffer.wrap_ansi(line, width)
      end

      def resolved_list_width(context)
        value = resolve(:list_width, context)
        value.is_a?(Rational) ? (context.cols * value).to_i : value
      end

      def action_descriptor(action, context)
        run = action[:run]
        action.except(:run).merge(on_click: lambda do |window|
          item = window.list_widget.selected_item
          context.instance_exec(item, &run) if run && (item || run.arity.zero?)
          :keep
        end)
      end

      def button_descriptor(button, context)
        run = button[:run]
        button.except(:run).merge(on_click: lambda do |_window|
          context.kept = false
          context.instance_exec(&run) if run
          context.kept ? :keep : nil
        end)
      end

      def submit_callback(context)
        submit = @attrs[:on_submit]
        return nil unless submit

        lambda do |values, form|
          context.kept = false
          result = context.instance_exec(values, &submit)
          return refuse(form, @errors[result]) if result.is_a?(Symbol) && @errors.key?(result)

          context.kept ? :keep : :close
        rescue Refused => e
          refuse(form, e.message)
        end
      end

      def refuse(form, message)
        form.error(message)
        :keep
      end

      def resolve_fields(context)
        prefilled = @attrs[:prefill] ? Hash(resolve(:prefill, context)).transform_keys(&:to_sym) : {}
        @fields.map do |field|
          value = field[:value]
          value = context.instance_exec(&value) if value.is_a?(Proc)
          value = prefilled[field[:key]] if value.nil? && prefilled.key?(field[:key])
          field.merge(value: value)
        end
      end
    end
  end
end
