# frozen_string_literal: true

module BBS
  # A single-screen page router: a set of named pages, each with its own
  # render block and key bindings, drawn by BBS::TUIRunner with frame-buffer
  # delta rendering. The blocks run inside a BBS::TUIRunner::Context, which
  # provides the drawing primitives; returning +:halt+ from a key binding
  # ends the TUI.
  #
  #   DASH = BBS::TUI.define do
  #     start :main
  #     page :main do
  #       render { text 'Hello', x: 2, y: 2 }
  #       key(:escape) { :halt }
  #     end
  #   end
  class TUI
    # The #init block, the #chrome block, the pages (a Hash of name to
    # Page), the name of the first page, and the Module of #helpers.
    attr_reader :init_block, :chrome_block, :pages, :start_page, :helper_module

    # Builds a TUI by evaluating the block in a new instance, and returns it.
    def self.define(&block)
      tui = new
      tui.instance_eval(&block)
      tui
    end

    # Creates a TUI with no pages and +:idle+ as the start page.
    def initialize
      @pages         = {}
      @start_page    = :idle
      @helper_module = Module.new
    end

    # Sets the block that runs once in the context before the first page.
    def init(&block)   = @init_block   = block
    # Sets the block drawn on every render before the current page.
    def chrome(&block) = @chrome_block = block
    # Sets the name of the page shown first.
    def start(name)    = @start_page   = name

    # Evaluates the block in the helper Module; the methods it defines can be
    # called from every page block.
    def helpers(&block)
      @helper_module.module_eval(&block)
    end

    # Defines the page +name+ by evaluating the block in a new Page.
    #
    # Returns the Page.
    def page(name, &block)
      page_definition = Page.new(name)
      page_definition.instance_eval(&block)
      @pages[name] = page_definition
    end

    # One page of a TUI: what runs on entering it, what it draws, and its
    # key bindings. The blocks run in a BBS::TUIRunner::Context.
    class Page
      # The page name, the #enter block, the #render block, and the key
      # bindings (a Hash of key to block; +:printable+, +:mouse+ and +:any+
      # hold the catch-all handlers).
      attr_reader :name, :enter_block, :render_block, :key_bindings

      # Creates a page called +name+ with no blocks.
      def initialize(name)
        @name         = name
        @key_bindings = {}
      end

      # Sets the block that runs each time the page is entered.
      def enter(&block)     = @enter_block  = block
      # Sets the block that draws the page on every render.
      def render(&block)    = @render_block = block
      # Binds the key +k+ (a Symbol such as +:enter+, or a one-character
      # String) to the block.
      def key(k, &block)    = (@key_bindings[k] = block)
      # Sets the block called with a printable character that has no binding
      # of its own.
      def printable(&block) = (@key_bindings[:printable] = block)
      # Sets the block called with each BBS::Telnet::MouseEvent.
      def mouse(&block)     = (@key_bindings[:mouse] = block)
      # Sets the block called with any key nothing else handled.
      def any_key(&block)   = (@key_bindings[:any] = block)

      # Installs ready-made navigation key bindings. Option values may be
      # Procs, evaluated in the context on each key press, or plain values.
      #
      # [:menu]   Up/Down move <tt>@menu_selection</tt> over +size:+ entries,
      #           wrapping around
      # [:cycle]  Up/Down move <tt>@item_selection</tt> over +@items+,
      #           wrapping around
      # [:list]   Up/Down, Page Up/Down, Home and End move
      #           <tt>@item_selection</tt> over +@items+ and keep +@scroll+
      #           so the selection stays within +window:+ rows
      # [:scroll] the same keys move +@scroll+ over the +content:+ lines
      #           shown +window:+ rows at a time
      #
      #   nav :list, window: -> { term_rows - 6 }
      def nav(mode, **opts)
        coerce = ->(value) { value.is_a?(Proc) ? value : -> { value } }

        case mode
        when :menu
          size = coerce.(opts.fetch(:size))
          key(:up)   { n = instance_exec(&size); @menu_selection = (@menu_selection - 1) % n if n.positive? }
          key(:down) { n = instance_exec(&size); @menu_selection = (@menu_selection + 1) % n if n.positive? }

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
            next if @items.empty?

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
