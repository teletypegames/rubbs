# frozen_string_literal: true

require_relative 'windows/info'
require_relative 'windows/form'
require_relative 'windows/master_detail'
require_relative 'windows/stream'

module BBS
  # Declarative window definition used inside Application.define:
  #
  #   window :compose, type: :form do |w|
  #     w.title { |ctx| " Post to #{ctx[:board].title} " }
  #     w.width 70
  #     w.field :body, type: :textarea, max_length: 1000
  #     w.on_submit do |values, form, ctx|
  #       case ctx[:boards].post(ctx[:board].id, ctx[:username], values[:body])
  #       when :empty then form.error('Message cannot be empty.'); :keep
  #       else :close
  #       end
  #     end
  #   end
  #
  # `w.maximizable true` gives the window the zoom gadget (F5, Alt-Enter):
  # it fills the screen and back. Worth it for windows with a lot to read.
  #
  # Open with `app.open_window(:compose, board: some_board)`. Block callbacks
  # receive a `ctx` hash combining the app's services, app.context, and any
  # extras passed to open_window.
  class WindowSpec
    SCALAR_ATTRS = %i[
      title width height padding hint placeholder list_width buffer_size
      scroll close_button close_label empty_message submit_label cancel_label
      maximizable
    ].freeze

    BLOCK_ATTRS = %i[
      body items initial_lines item_label render_detail bottom_meta
      on_submit on_cancel on_poll on_activate prefill
    ].freeze

    attr_reader :name, :type

    def initialize(name, type:)
      @name    = name
      @type    = type
      @attrs   = {}
      @fields  = []
      @actions = []
      @buttons = nil
    end

    SCALAR_ATTRS.each do |key|
      define_method(key) { |value = nil, &block| @attrs[key] = block || value }
      alias_method "#{key}=", key
    end

    BLOCK_ATTRS.each do |key|
      define_method(key) { |value = nil, &block| @attrs[key] = block || value }
    end

    def field(key, **opts)
      @fields << opts.merge(key: key)
    end

    def action(**opts, &block)
      opts = opts.merge(on_click: block) if block
      @actions << opts
    end

    def button(**opts, &block)
      @buttons ||= []
      opts = opts.merge(on_click: block) if block
      @buttons << opts
    end

    # Resolves attrs + wraps callbacks with the runtime `ctx`, then opens the
    # underlying rubbs window. `extras` flow into `ctx` (e.g., `board:`).
    def open(app, **extras)
      ctx = build_ctx(app, extras)
      window = send("open_#{@type}", app, ctx)
      window.maximizable = resolve(:maximizable, ctx) ? true : false if window.respond_to?(:maximizable=)
      window
    end

    private

    def build_ctx(app, extras)
      services = app.respond_to?(:services) ? (app.services || {}) : {}
      context  = app.respond_to?(:context)  ? (app.context  || {}) : {}
      { app: app, **context, **services, **extras }
    end

    def resolve(key, ctx, *args)
      val = @attrs[key]
      val.is_a?(Proc) ? val.call(ctx, *args) : val
    end

    def open_info(app, ctx)
      kw = {
        title:   resolve(:title, ctx),
        body:    resolve(:body, ctx),
        width:   resolve(:width, ctx),
        height:  resolve(:height, ctx),
        scroll:  resolve(:scroll, ctx),
        padding: resolve(:padding, ctx)
      }.compact
      kw[:buttons] = build_buttons(ctx) if @buttons
      BBS::Windows::Info.open(app, **kw)
    end

    def open_form(app, ctx)
      on_submit = @attrs[:on_submit]
      on_cancel = @attrs[:on_cancel]
      kw = {
        title:        resolve(:title, ctx),
        fields:       resolve_fields(ctx),
        width:        resolve(:width, ctx),
        height:       resolve(:height, ctx),
        hint:         resolve(:hint, ctx),
        submit_label: resolve(:submit_label, ctx),
        cancel_label: resolve(:cancel_label, ctx)
      }.compact
      kw[:on_submit] = ->(values, form) { on_submit.call(values, form, ctx) } if on_submit
      kw[:on_cancel] = ->(form)         { on_cancel.call(form, ctx) }         if on_cancel
      BBS::Windows::Form.open(app, **kw)
    end

    def open_master_detail(app, ctx)
      label_cb  = @attrs[:item_label]
      render_cb = @attrs[:render_detail]
      meta_cb   = @attrs[:bottom_meta]
      activate  = @attrs[:on_activate]
      kw = {
        title:         resolve(:title, ctx),
        items:         resolve(:items, ctx) || [],
        item_label:    label_cb  ? ->(item)        { label_cb.call(item, ctx) }         : ->(x) { x.to_s },
        render_detail: render_cb ? ->(item, width) { render_cb.call(item, width, ctx) } : ->(_i, _w) { [] },
        list_width:    resolve(:list_width, ctx),
        empty_message: resolve(:empty_message, ctx),
        close_button:  resolve(:close_button, ctx),
        close_label:   resolve(:close_label, ctx),
        width:         resolve(:width, ctx),
        height:        resolve(:height, ctx)
      }.compact
      kw[:bottom_meta] = ->(item) { meta_cb.call(item, ctx) } if meta_cb
      kw[:on_activate] = ->(item, win) { activate.call(item, win, ctx) } if activate
      kw[:actions]     = build_actions(ctx) unless @actions.empty?
      BBS::Windows::MasterDetail.open(app, **kw)
    end

    def open_stream(app, ctx)
      on_submit = @attrs[:on_submit]
      on_poll   = @attrs[:on_poll]
      kw = {
        title:         resolve(:title, ctx),
        initial_lines: resolve(:initial_lines, ctx) || [],
        placeholder:   resolve(:placeholder, ctx),
        buffer_size:   resolve(:buffer_size, ctx),
        width:         resolve(:width, ctx),
        height:        resolve(:height, ctx),
        close_button:  resolve(:close_button, ctx),
        close_label:   resolve(:close_label, ctx)
      }.compact
      kw[:on_submit] = ->(text, app_) { on_submit.call(text, app_, ctx) } if on_submit
      kw[:on_poll]   = ->(app_)       { on_poll.call(app_, ctx) }         if on_poll
      BBS::Windows::Stream.open(app, **kw)
    end

    def resolve_fields(ctx)
      prefilled = if @attrs[:prefill]
                    Hash(@attrs[:prefill].call(ctx)).transform_keys(&:to_sym)
                  else
                    {}
                  end
      @fields.map do |f|
        value = f[:value]
        value = value.call(ctx) if value.is_a?(Proc)
        value = prefilled[f[:key]] if value.nil? && prefilled.key?(f[:key])
        f.merge(value: value)
      end
    end

    def build_buttons(ctx) = @buttons.map { |b| wrap_clickable(b, ctx) }
    def build_actions(ctx) = @actions.map { |a| wrap_clickable(a, ctx) }

    def wrap_clickable(opts, ctx)
      return opts unless opts[:on_click].is_a?(Proc)
      cb = opts[:on_click]
      opts.merge(on_click: ->(win) { cb.call(win, ctx) })
    end
  end
end
