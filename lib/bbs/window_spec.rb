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
  # <tt>w.maximizable true</tt> gives the window the zoom gadget (F5,
  # Alt-Enter): it fills the screen and back. Worth it for windows with a lot
  # to read.
  #
  # Open with <tt>app.open_window(:compose, board: some_board)</tt>. Block
  # callbacks receive a +ctx+ hash combining the app's services, app.context,
  # and any extras passed to open_window.
  #
  # The +type+ picks the window class: +:info+ (BBS::Windows::Info), +:form+
  # (BBS::Windows::Form), +:master_detail+ (BBS::Windows::MasterDetail) or
  # +:stream+ (BBS::Windows::Stream). Each name in SCALAR_ATTRS and
  # BLOCK_ATTRS is a setter method that takes a value or a block; a block
  # is called with +ctx+ (and the callback's own arguments first, for the
  # callbacks) when the window opens.
  class WindowSpec
    # The attributes usually given as plain values, each a setter method
    # with an <tt>=</tt> alias; a block given instead is called with +ctx+.
    SCALAR_ATTRS = %i[
      title width height padding hint placeholder list_width buffer_size
      scroll close_button close_label empty_message submit_label cancel_label
      maximizable accent
    ].freeze

    # The attributes usually given as blocks: content (+body+, +items+,
    # +initial_lines+, +prefill+), item rendering (+item_label+,
    # +render_detail+, +bottom_meta+) and callbacks (+on_submit+,
    # +on_cancel+, +on_poll+, +on_activate+). Each is a setter method that
    # takes a value or a block.
    BLOCK_ATTRS = %i[
      body items initial_lines item_label render_detail bottom_meta
      on_submit on_cancel on_poll on_activate prefill
    ].freeze

    # The window class of each type.
    WINDOWS = {
      info: Windows::Info, form: Windows::Form, master_detail: Windows::MasterDetail, stream: Windows::Stream
    }.freeze
    # The attributes each type passes to its window's +open+, resolved
    # with +ctx+; a +nil+ one is left out.
    VALUES = {
      info:          %i[title body width height scroll padding],
      form:          %i[title width height hint submit_label cancel_label],
      master_detail: %i[title items list_width empty_message close_button close_label width height],
      stream:        %i[title initial_lines placeholder buffer_size width height close_button close_label]
    }.freeze
    # The callbacks each type passes on, called with their own arguments
    # and +ctx+ last.
    CALLBACKS = {
      info:          [],
      form:          %i[on_submit on_cancel],
      master_detail: %i[item_label render_detail bottom_meta on_activate],
      stream:        %i[on_submit on_poll]
    }.freeze
    # What a type's window gets for an attribute that is not set.
    DEFAULTS = {
      master_detail: { items: [], item_label: :to_s.to_proc, render_detail: ->(_item, _width) { [] } },
      stream:        { initial_lines: [] }
    }.freeze

    # The window's name (as used with +open_window+) and its type Symbol.
    attr_reader :name, :type

    # Creates an empty spec for the window +name+ of +type+ (+:info+,
    # +:form+, +:master_detail+ or +:stream+).
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

    # Adds a form field stored under +key+. +opts+ is a
    # BBS::Windows::Form field descriptor (+label+, +type+, +max_length+,
    # ...); a Proc +value+ is called with +ctx+, and a field without a value
    # takes it from the +prefill+ Hash.
    def field(key, **opts)
      @fields << opts.merge(key: key)
    end

    # Adds an action button to a master/detail window. +opts+ is a
    # BBS::Windows::ButtonBar descriptor; the block, when given, becomes its
    # +on_click+ and is called with the window and +ctx+.
    def action(**opts, &block)
      opts = opts.merge(on_click: block) if block
      @actions << opts
    end

    # Adds a button to an info window, replacing its default OK button.
    # +opts+ is a BBS::Windows::ButtonBar descriptor; the block, when given,
    # becomes its +on_click+ and is called with the window and +ctx+.
    def button(**opts, &block)
      @buttons ||= []
      opts = opts.merge(on_click: block) if block
      @buttons << opts
    end

    # Resolves the attributes, wraps the callbacks with the runtime +ctx+,
    # then opens the underlying rubbs window on +app+. +extras+ flow into
    # +ctx+ (e.g. <tt>board:</tt>).
    #
    # Returns the opened BBS::Window.
    def open(app, **extras)
      ctx    = build_ctx(app, extras)
      window = WINDOWS.fetch(@type).open(app, **options(ctx))
      window.maximizable = resolve(:maximizable, ctx) ? true : false if window.respond_to?(:maximizable=)
      window.accent = resolve(:accent, ctx) if window.respond_to?(:accent=)
      window
    end

    private

    def build_ctx(app, extras)
      services = app.respond_to?(:services) ? (app.services || {}) : {}
      context  = app.respond_to?(:context)  ? (app.context  || {}) : {}
      { app: app, **context, **services, **extras }
    end

    def resolve(key, ctx, *)
      val = @attrs[key]
      val.is_a?(Proc) ? val.call(ctx, *) : val
    end

    # The keywords of the window's +open+: the defaults, the VALUES set,
    # the CALLBACKS bound to +ctx+, and the type's own parts.
    def options(ctx)
      values    = VALUES.fetch(@type).to_h { |key| [key, resolve(key, ctx)] }.compact
      callbacks = CALLBACKS.fetch(@type).filter_map { |key| [key, bind(@attrs[key], ctx)] if @attrs[key] }.to_h
      DEFAULTS.fetch(@type, {}).merge(values, callbacks, parts(ctx))
    end

    # +callback+ called with its own arguments and +ctx+ last.
    def bind(callback, ctx) = ->(*args) { callback.call(*args, ctx) }

    # The fields of a form, the buttons of an info window, the actions of a
    # master/detail window.
    def parts(ctx)
      case @type
      when :form then { fields: resolve_fields(ctx) }
      when :info then @buttons ? { buttons: clickables(@buttons, ctx) } : {}
      when :master_detail then @actions.empty? ? {} : { actions: clickables(@actions, ctx) }
      else {}
      end
    end

    def resolve_fields(ctx)
      prefilled = @attrs[:prefill] ? Hash(@attrs[:prefill].call(ctx)).transform_keys(&:to_sym) : {}
      @fields.map { |field| field.merge(value: field_value(field, prefilled, ctx)) }
    end

    # The value of +field+: its own (a Proc called with +ctx+), else the
    # +prefilled+ one.
    def field_value(field, prefilled, ctx)
      value = field[:value]
      value = value.call(ctx) if value.is_a?(Proc)
      value.nil? && prefilled.key?(field[:key]) ? prefilled[field[:key]] : value
    end

    # Button descriptors with their +on_click+ Proc bound to +ctx+.
    def clickables(list, ctx)
      list.map { |opts| opts[:on_click].is_a?(Proc) ? opts.merge(on_click: bind(opts[:on_click], ctx)) : opts }
    end
  end
end
