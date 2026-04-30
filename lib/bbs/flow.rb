# frozen_string_literal: true

module BBS
  class Flow
    attr_reader :steps

    def self.define(&block)
      flow = new
      flow.instance_eval(&block)
      flow.freeze
    end

    def initialize
      @steps = []
    end

    def screen(name, **vars)
      @steps << { type: :screen, name: name, vars: vars }
    end

    def banner(text, style: :success)
      @steps << { type: :banner, text: text, style: style }
    end

    def big_banner(text, style: :success, font: 'slant')
      @steps << { type: :big_banner, text: text, style: style, font: font }
    end

    def say(text, style: :muted)
      @steps << { type: :say, text: text, style: style }
    end

    def set(name, value)
      @steps << { type: :set, name: name, value: value }
    end

    def ask(name, prompt:, transform: nil, validate: nil)
      @steps << { type: :ask, name: name, prompt: prompt,
                  transform: transform, validate: validate }
    end

    def persist(*fields, store:)
      @steps << { type: :persist, fields: fields.flatten, store: store }
    end

    def pause(message, seconds: 1.0)
      @steps << { type: :pause, message: message, seconds: seconds }
    end

    def gate(denied:, &check)
      @steps << { type: :gate, check: check, denied: denied }
    end

    def confirm(message, denied: nil, &block)
      step = { message: message, denied: denied }
      if block_given?
        sub = Flow.new
        sub.instance_eval(&block)
        @steps << step.merge(type: :confirm_block, sub_steps: sub.steps)
      else
        @steps << step.merge(type: :confirm_halt)
      end
    end

    def menu(prompt, loop: false, &block)
      builder = MenuBuilder.new
      builder.instance_eval(&block)
      @steps << { type: :menu, prompt: prompt, loop: loop, options: builder.options }
    end

    def exit_menu
      @steps << { type: :exit_menu }
    end

    def call(&block)
      @steps << { type: :call, block: block }
    end

    def line(color: :muted)
      @steps << { type: :line, color: color }
    end

    def section(title, color: :confirm)
      @steps << { type: :section, title: title, color: color }
    end

    def text(content = nil, style: :muted, &block)
      @steps << { type: :text, text: content, block: block, style: style }
    end

    def rows(empty: 'No items.', &block)
      @steps << { type: :rows, block: block, empty: empty }
    end

    def table(&block)
      @steps << { type: :table, block: block }
    end

    def wait_enter(prompt: 'Press ENTER to continue...')
      @steps << { type: :wait_enter, prompt: prompt }
    end

    def fetch(name, loading: 'Loading...', &block)
      @steps << { type: :fetch, name: name, loading: loading, block: block }
    end

    def pick(from:, prompt:, empty: 'No items.', item:, hint: nil, &block)
      sub = Flow.new
      sub.instance_eval(&block) if block_given?
      @steps << { type: :pick, from: from, prompt: prompt, empty: empty,
                  item: item, hint: hint, sub_steps: sub.steps }
    end

    def body(width: 66, indent: 4, &block)
      @steps << { type: :body, block: block, width: width, indent: indent }
    end

    def output(&block)
      @steps << { type: :output, block: block }
    end
  end

  class MenuBuilder
    attr_reader :options

    def initialize
      @options = []
    end

    def option(label, &block)
      sub = Flow.new
      sub.instance_eval(&block) if block_given?
      @options << { label: label, steps: sub.steps }
    end
  end
end
