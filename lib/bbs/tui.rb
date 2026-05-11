# frozen_string_literal: true

module BBS
  class TUI
    attr_reader :init_block, :render_block, :key_bindings

    def self.define(&block)
      tui = new
      tui.instance_eval(&block)
      tui.freeze
    end

    def initialize
      @key_bindings = {}
    end

    def init(&block)
      @init_block = block
    end

    def render(&block)
      @render_block = block
    end

    def key(k, action = nil, &block)
      @key_bindings[k] = action || block
    end
  end
end
