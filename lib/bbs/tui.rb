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
      @pages      = {}
      @start_page = :idle
    end

    def init(&block)   = @init_block   = block
    def chrome(&block) = @chrome_block = block
    def start(name)    = @start_page   = name

    def helpers(&block)
      @helper_module = Module.new(&block)
    end

    def page(name, &block)
      p = Page.new(name)
      p.instance_eval(&block)
      @pages[name] = p
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
    end
  end
end
