# frozen_string_literal: true

module BBS
  # A line-mode script for a caller: a list of steps that BBS::FlowRunner
  # runs in order on the session. Each DSL method below appends one step;
  # nothing is written to the caller while the flow is defined.
  #
  # Steps share a context Hash (+ctx+) that holds +:session_id+ and the
  # values that #ask, #set, #fetch and #pick store. A step that reads a
  # line ends the flow when the caller hangs up.
  #
  #   FLOW = BBS::Flow.define do
  #     screen :welcome
  #     ask :name, prompt: 'Your name', transform: :upcase, validate: :non_empty
  #     say 'Nice to meet you.'
  #     menu 'Choose:', loop: true do
  #       option('Who am I') { text { |ctx| ctx[:name] } }
  #       option('Leave')    { exit_menu }
  #     end
  #   end
  class Flow
    # The steps as an Array of Hash (each with a +:type+), and the folder
    # the #screen steps read from (or +nil+).
    attr_reader :steps, :screens_dir

    # Builds a flow by evaluating the block in a new Flow, and returns it
    # frozen.
    #
    # +screens_dir+ is where this flow's #screen steps find their ERB files;
    # without it they use <tt>BBS.config.screens_dir</tt>. A flow that ships
    # with its own screens (a door from a gem) names its folder here.
    def self.define(screens_dir: nil, &block)
      flow = new(screens_dir: screens_dir)
      flow.instance_eval(&block)
      flow.freeze
    end

    # Creates an empty flow. Flow.define is the usual way to build one.
    def initialize(screens_dir: nil)
      @steps       = []
      @screens_dir = screens_dir
    end

    # Renders the ERB screen +name+ from the screens folder and writes it.
    # The template sees the context plus +vars+; a Symbol value in +vars+ is
    # looked up in the context.
    def screen(name, **vars)
      @steps << { type: :screen, name: name, vars: vars }
    end

    # Writes +text+ in a boxed banner (see BBS::Banner) in the colour named
    # by +style+, one of the BBS::FlowRunner::STYLES keys.
    def banner(text, style: :success)
      @steps << { type: :banner, text: text, style: style }
    end

    # Writes +text+ as large FIGlet letters in +font+, coloured by +style+.
    def big_banner(text, style: :success, font: 'slant')
      @steps << { type: :big_banner, text: text, style: style, font: font }
    end

    # Writes +text+ as an indented paragraph with a blank line around it.
    def say(text, style: :muted)
      @steps << { type: :say, text: text, style: style }
    end

    # Stores +value+ in the context under +name+.
    def set(name, value)
      @steps << { type: :set, name: name, value: value }
    end

    # Prints +prompt+, reads a line, and stores it stripped in the context
    # under +name+.
    #
    # [transform] +:upcase+, +:downcase+, or a Proc applied to the answer
    # [validate]  +:email+, +:non_empty+, or a Proc or Method that returns
    #             truthy for a good answer; a bad answer prints an error and
    #             ends the flow
    def ask(name, prompt:, transform: nil, validate: nil)
      @steps << { type: :ask, name: name, prompt: prompt,
                  transform: transform, validate: validate }
    end

    # Saves the context values of +fields+ (those present) to +store+, a
    # BBS::Store, in the row of the session id.
    def persist(*fields, store:)
      @steps << { type: :persist, fields: fields.flatten, store: store }
    end

    # Writes +message+ and sleeps for +seconds+.
    def pause(message, seconds: 1.0)
      @steps << { type: :pause, message: message, seconds: seconds }
    end

    # Calls the block with the context; when it returns falsy, writes
    # +denied+ and ends the flow.
    def gate(denied:, &check)
      @steps << { type: :gate, check: check, denied: denied }
    end

    # Asks +message+ with a <tt>[yes/no]</tt> prompt. With a block, the
    # steps defined in the block run on yes and the flow goes on either way.
    # Without a block, the flow goes on only on yes. On no, +denied+ is
    # written when given.
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

    # Shows a numbered menu of the options declared in the block with
    # MenuBuilder#option, reads a number, and runs that option's steps. An
    # out-of-range answer asks again. With +loop+ the menu comes back after
    # each option until one runs #exit_menu.
    def menu(prompt, loop: false, &block)
      builder = MenuBuilder.new
      builder.instance_eval(&block)
      @steps << { type: :menu, prompt: prompt, loop: loop, options: builder.options }
    end

    # Leaves the innermost menu; the flow goes on after it.
    def exit_menu
      @steps << { type: :exit_menu }
    end

    # Calls the block with the context and the BBS::FlowRunner. Returning
    # +:halt+ ends the flow; an error is logged and shown to the caller, and
    # the flow goes on.
    def call(&block)
      @steps << { type: :call, block: block }
    end

    # Writes a horizontal rule. +color+ is a STYLES key or an SGR string.
    def line(color: :muted)
      @steps << { type: :line, color: color }
    end

    # Writes a section heading with +title+ on a box-drawing rule.
    def section(title, color: :confirm)
      @steps << { type: :section, title: title, color: color }
    end

    # Writes one indented line: +content+, or the block's return value
    # (called with the context). Nothing is written for +nil+.
    def text(content = nil, style: :muted, &block)
      @steps << { type: :text, text: content, block: block, style: style }
    end

    # Writes each element the block returns (called with the context) on
    # its own indented line, or +empty+ when there are none.
    def rows(empty: 'No items.', &block)
      @steps << { type: :rows, block: block, empty: empty }
    end

    # Writes the label/value pairs the block returns (called with the
    # context) as two aligned columns.
    def table(&block)
      @steps << { type: :table, block: block }
    end

    # Writes +prompt+ and waits for ENTER.
    def wait_enter(prompt: 'Press ENTER to continue...')
      @steps << { type: :wait_enter, prompt: prompt }
    end

    # Writes +loading+, calls the block with the context, removes the
    # loading line, and stores the result in the context under +name+.
    def fetch(name, loading: 'Loading...', &block)
      @steps << { type: :fetch, name: name, loading: loading, block: block }
    end

    # Lists up to 25 elements of the context Array under +from+, numbered,
    # and asks for one. Each line is <tt>item.call(element, number)</tt>,
    # with an optional muted <tt>hint.call(element, number)</tt> line below.
    # The chosen element is stored in the context as +:picked+ and the steps
    # of the block run; an empty answer skips them. With no elements, +empty+
    # is shown instead.
    def pick(from:, prompt:, empty: 'No items.', item:, hint: nil, &block)
      sub = Flow.new
      sub.instance_eval(&block) if block_given?
      @steps << { type: :pick, from: from, prompt: prompt, empty: empty,
                  item: item, hint: hint, sub_steps: sub.steps }
    end

    # Writes the block's text (called with the context) with Markdown marks
    # removed, word-wrapped to +width+ columns and indented by +indent+.
    def body(width: 66, indent: 4, &block)
      @steps << { type: :body, block: block, width: width, indent: indent }
    end

    # Writes the block's return value (called with the context) as it is.
    def output(&block)
      @steps << { type: :output, block: block }
    end

    # Runs the full-screen BBS::TUI +definition+ with BBS::TUIRunner.
    def tui(definition)
      @steps << { type: :tui, definition: definition }
    end

    # Runs the windowed BBS::Application +definition+ on the session.
    def app(definition)
      @steps << { type: :app, definition: definition }
    end

    # Runs the BBS::FakeOS::Definition +definition+ on the session.
    def os(definition)
      @steps << { type: :os, definition: definition }
    end
  end

  # Collects the options of a Flow#menu block.
  class MenuBuilder
    # The options as an Array of Hash with +:label+ and +:steps+.
    attr_reader :options

    # Creates a builder with no options.
    def initialize
      @options = []
    end

    # Adds an option labelled +label+ whose steps are the Flow steps defined
    # in the block.
    def option(label, &block)
      sub = Flow.new
      sub.instance_eval(&block) if block_given?
      @options << { label: label, steps: sub.steps }
    end
  end
end
