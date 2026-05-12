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
      def mouse(&block)     = (@key_bindings[:mouse] = block)
      def any_key(&block)   = (@key_bindings[:any] = block)

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
            next if @item_selection <= 0
            @item_selection -= 1
            @scroll = @item_selection if @item_selection < @scroll
          end
          key(:down) do
            next if @item_selection >= @items.size - 1
            @item_selection += 1
            window_size = instance_exec(&window)
            @scroll = @item_selection - window_size + 1 if @item_selection >= @scroll + window_size
          end
          key(:page_up) do
            next if @item_selection <= 0
            step = instance_exec(&window)
            @item_selection = [@item_selection - step, 0].max
            @scroll = [@scroll - step, 0].max
          end
          key(:page_down) do
            next if @item_selection >= @items.size - 1
            step = instance_exec(&window)
            @item_selection = [@item_selection + step, @items.size - 1].min
            @scroll = [[@scroll + step, @item_selection].min, [@items.size - step, 0].max].min
          end
          key(:home) { @item_selection = 0; @scroll = 0 }
          key(:end)  do
            step = instance_exec(&window)
            @item_selection = @items.size - 1
            @scroll = [@items.size - step, 0].max
          end

        when :scroll
          content = opts.fetch(:content)
          window  = coerce.(opts.fetch(:window))
          key(:up)   { @scroll = [@scroll - 1, 0].max }
          key(:down) do
            max = [instance_exec(&content).size - instance_exec(&window), 0].max
            @scroll = [@scroll + 1, max].min
          end
          key(:page_up)   { @scroll = [@scroll - instance_exec(&window), 0].max }
          key(:page_down) do
            max = [instance_exec(&content).size - instance_exec(&window), 0].max
            @scroll = [@scroll + instance_exec(&window), max].min
          end
          key(:home) { @scroll = 0 }
          key(:end)  do
            @scroll = [instance_exec(&content).size - instance_exec(&window), 0].max
          end
        end
      end
    end
  end
end
