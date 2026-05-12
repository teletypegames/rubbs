# frozen_string_literal: true

module BBS
  class TUI
    attr_reader :init_block, :chrome_block, :pages, :start_page, :helper_module

    def self.define(&block)
      tui = new
      tui.instance_eval(&block)
      tui
    end

    def initialize
      @pages         = {}
      @start_page    = :idle
      @helper_module = Module.new
    end

    def init(&block)   = @init_block   = block
    def chrome(&block) = @chrome_block = block
    def start(name)    = @start_page   = name

    def helpers(&block)
      @helper_module.module_eval(&block)
    end

    def page(name, &block)
      page_definition = Page.new(name)
      page_definition.instance_eval(&block)
      @pages[name] = page_definition
    end

    class Page
      attr_reader :name, :enter_block, :render_block, :key_bindings

      def initialize(name)
        @name         = name
        @key_bindings = {}
      end

      def enter(&block)     = @enter_block  = block
      def render(&block)    = @render_block = block
      def key(k, &block)    = (@key_bindings[k] = block)
      def printable(&block) = (@key_bindings[:printable] = block)

      def nav(mode, **opts)
        coerce = ->(value) { value.is_a?(Proc) ? value : -> { value } }

        case mode
        when :menu
          size = coerce.(opts.fetch(:size))
          key(:up)   { @menu_selection = (@menu_selection - 1) % instance_exec(&size) }
          key(:down) { @menu_selection = (@menu_selection + 1) % instance_exec(&size) }

        when :cycle
          key(:up)   { @item_selection = (@item_selection - 1) % @items.size if @items.any? }
          key(:down) { @item_selection = (@item_selection + 1) % @items.size if @items.any? }

        when :list
          window = coerce.(opts.fetch(:window))
          key(:up) do
            return if @item_selection <= 0
            @item_selection -= 1
            @scroll = @item_selection if @item_selection < @scroll
          end
          key(:down) do
            return if @item_selection >= @items.size - 1
            @item_selection += 1
            window_size = instance_exec(&window)
            @scroll = @item_selection - window_size + 1 if @item_selection >= @scroll + window_size
          end

        when :scroll
          content = opts.fetch(:content)
          window  = coerce.(opts.fetch(:window))
          key(:up)   { @scroll = [@scroll - 1, 0].max }
          key(:down) do
            max = [instance_exec(&content).size - instance_exec(&window), 0].max
            @scroll = [@scroll + 1, max].min
          end
        end
      end
    end
  end
end
