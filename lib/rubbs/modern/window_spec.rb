# frozen_string_literal: true

require_relative 'windows/info'
require_relative 'windows/form'
require_relative 'windows/master_detail'
require_relative 'windows/stream'
require_relative 'windows/reader'
require_relative 'window_context'
require_relative 'window_spec/options'
require_relative 'window_spec/reader_options'

module Rubbs
  module Modern
    # A window declared in Application.define, opened with
    # <tt>show(:name, **extras)</tt>:
    #
    #   window :article, :master_detail do
    #     title  { article.title }
    #     items  { article.sections }
    #     label  :title
    #     detail { |section| markdown(section.markdown) }
    #     meta   { "#{article.url} · CC BY-SA" }
    #     action('QR code') { qr article.short_url, title: 'Scan the article' }
    #   end
    #
    #   show :article, article: found
    #
    # The block is evaluated in the spec; each attribute takes a value or a
    # block. A block runs when the window opens (or, for the callbacks, when
    # the caller acts) in a Rubbs::Modern::WindowContext: the application's helpers,
    # services and methods, the +extras+ of Application#show as methods (+article+), and
    # +window+, +close+, +keep+, +error!+.
    #
    # The types:
    #
    # [+:info+]          text and buttons (Rubbs::Modern::Windows::Info): +body+,
    #                    +scroll+, +padding+, #button
    # [+:form+]          fields and Save/Cancel (Rubbs::Modern::Windows::Form): #field,
    #                    +hint+, +prefill+, +on_submit+, +on_cancel+, #errors,
    #                    +submit_label+, +cancel_label+
    # [+:master_detail+] a list and the picked item (Rubbs::Modern::Windows::MasterDetail):
    #                    +items+, +label+, +detail+, +meta+, +on_pick+,
    #                    #action, +list_width+, +empty+
    # [+:stream+]        a log and an input line (Rubbs::Modern::Windows::Stream):
    #                    +lines+, +placeholder+, +buffer_size+, +on_submit+,
    #                    +on_poll+
    # [+:reader+]        a long text to page through (Rubbs::Modern::Windows::Reader):
    #                    +lines+, +where+, +max_width+, #action, +on_key+ (a
    #                    Hash of keys to blocks taking the reader)
    #
    # Every type takes +title+ (padded by the frame), +width+ and +height+
    # (a negative number counts back from the screen's size), +maximizable+
    # (on by default for a master/detail, a stream and a reader), +maximized+
    # (opens full screen) and
    # +accent+ (a Hash of theme roles for this window only).
    class WindowSpec
      include Options
      include ReaderOptions

      # The attributes: each a method taking a value or a block.
      ATTRS = %i[
        title width height maximizable accent padding scroll body hint submit_label cancel_label prefill
        on_submit on_cancel items label detail meta on_pick list_width empty close_button close_label
        lines placeholder buffer_size on_poll where max_width maximized on_key
      ].freeze

      # The window class of each type.
      WINDOWS = {
        info:          Windows::Info,
        form:          Windows::Form,
        master_detail: Windows::MasterDetail,
        stream:        Windows::Stream,
        reader:        Windows::Reader
      }.freeze

      # The types whose windows are maximizable unless the spec says.
      MAXIMIZABLE = %i[master_detail stream reader].freeze

      # Raised inside a form's +on_submit+ by WindowContext#error! to show a
      # message and keep the form open.
      class Refused < StandardError
      end

      # The window's name (as used with Application#show) and its type Symbol.
      attr_reader :name, :type

      # Creates the spec of window +name+ of +type+ (a key of WINDOWS) and
      # evaluates the block in it. Raises ArgumentError for an unknown type.
      def initialize(name, type, &block)
        raise ArgumentError, "Unknown window type: #{type.inspect}" unless WINDOWS.key?(type)

        @name    = name
        @type    = type
        @attrs   = {}
        @fields  = []
        @actions = []
        @buttons = nil
        @errors  = {}
        instance_eval(&block) if block
      end

      ATTRS.each do |key|
        define_method(key) { |value = nil, &block| @attrs[key] = block || value }
      end

      # Adds a form field stored under +key+. +opts+ is a Rubbs::Modern::Windows::Form
      # field descriptor (+label+, +type+, +max_length+, …); a block +value+
      # is evaluated when the form opens, and a field without a value takes it
      # from +prefill+.
      def field(key, **opts)
        @fields << opts.merge(key: key)
      end

      # The messages of a form's refusals: when +on_submit+ returns one of
      # these keys, the form shows its message and stays open.
      #
      #   errors empty: 'Write something first.', too_fast: 'One post a minute, please.'
      def errors(messages) = @errors.merge!(messages)

      # Adds a button under a master/detail list or a reader. The block runs
      # with the selected item (a master/detail; a block that takes it does not
      # run on an empty list, one without a parameter always runs) and the
      # window stays open unless the block calls +close+.
      # +opts+ are those of Rubbs::Modern::Windows::ButtonBar (+align+, +key+).
      #
      #   action('Open') { |book| read(book) }
      def action(label, **opts, &block)
        @actions << opts.merge(label: menu_label(label), run: block)
      end

      # Adds a button to an info window, in place of its OK button. The block
      # runs, then the window closes unless the block calls +keep+.
      def button(label, **opts, &block)
        (@buttons ||= []) << opts.merge(label: menu_label(label), run: block)
      end

      # Opens the window on +app+: a Rubbs::Modern::WindowContext with +extras+, the
      # attributes resolved in it, the window made. Returns the Rubbs::Modern::Window.
      def open(app, **extras)
        context = WindowContext.new(app, extras)
        window  = WINDOWS.fetch(@type).open(app, **options(context))
        context.window = window
        window.id = @name
        window.maximizable = maximizable?(context)
        window.toggle_maximize if resolve(:maximized, context) && window.respond_to?(:toggle_maximize)
        window.accent = resolve(:accent, context) if @attrs.key?(:accent)
        window
      end

      private

      def menu_label(label) = label.include?('&') ? label : "&#{label}"

      def maximizable?(context)
        if @attrs.key?(:maximizable)
          resolve(:maximizable, context) ? true : false
        else
          MAXIMIZABLE.include?(@type)
        end
      end

      def resolve(key, context)
        value = @attrs[key]
        value.is_a?(Proc) ? context.instance_exec(&value) : value
      end

      def size(key, context, total)
        value = resolve(key, context)
        value.is_a?(Integer) && value.negative? ? total + value : value
      end
    end
  end
end
