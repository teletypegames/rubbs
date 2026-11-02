# frozen_string_literal: true

require_relative 'flow/steps'

module BBS
  # A line-mode script for a caller: a list of steps that BBS::FlowRunner
  # runs in order on the session. Each DSL method below appends one step
  # (a Flow::Steps object); nothing is written to the caller while the flow
  # is defined.
  #
  # Steps share a context Hash that holds +:session_id+ and the answers of
  # #ask. A step that reads a line ends the flow when the caller hangs up.
  # Most boards use a Flow as glue only: a #call step that runs the board's
  # own screen, then another for the goodbye.
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
    # The steps, an Array of Flow::Steps objects, and the folder the
    # #screen steps read from (or +nil+).
    attr_reader :steps, :screens_dir

    # Builds a flow by evaluating the block in a new Flow, and returns it
    # frozen.
    #
    # +screens_dir+ is where this flow's #screen steps find their ERB files;
    # without it they use <tt>BBS.config.screens_dir</tt>. A flow that ships
    # with its own screens (a door from a gem) names its folder here.
    def self.define(screens_dir: nil, &)
      flow = new(screens_dir: screens_dir)
      flow.instance_eval(&)
      flow.freeze
    end

    # The steps of the block, evaluated in a new Flow: the body of a
    # #confirm or of a menu option.
    def self.steps(&)
      return [] unless block_given?

      flow = new
      flow.instance_eval(&)
      flow.steps
    end

    # Creates an empty flow. Flow.define is the usual way to build one.
    def initialize(screens_dir: nil)
      @steps       = []
      @screens_dir = screens_dir
    end

    # Renders the ERB screen +name+ from the screens folder and writes it.
    # The template sees the context plus +vars+; a Symbol value in +vars+ is
    # looked up in the context.
    def screen(name, **vars) = add(Steps::Screen.new(name, vars))

    # Writes +text+ in a boxed banner (see BBS::Banner) in the colour of
    # +style+, a key of BBS::FlowRunner::STYLES.
    def banner(text, style: :success) = add(Steps::Banner.new(text, style))

    # Writes +text+ as large FIGlet letters in +font+, coloured by +style+.
    def big_banner(text, style: :success, font: 'slant') = add(Steps::BigBanner.new(text, style, font))

    # Writes +text+ as an indented paragraph with a blank line around it.
    def say(text, style: :muted) = add(Steps::Say.new(text, style))

    # Writes one indented line: +content+, or the block's return value
    # (called with the context). Nothing is written for +nil+.
    def text(content = nil, style: :muted, &block) = add(Steps::Text.new(content, block, style))

    # Prints +prompt+, reads a line, and stores it stripped in the context
    # under +name+.
    #
    # [transform] +:upcase+, +:downcase+, or a Proc applied to the answer
    # [validate]  +:email+, +:non_empty+, or a Proc or Method that returns
    #             truthy for a good answer; a bad answer prints an error and
    #             ends the flow
    def ask(name, prompt:, transform: nil, validate: nil)
      add(Steps::Ask.new(name, prompt, transform, validate))
    end

    # Saves the context values of +fields+ (those present) to +store+, a
    # BBS::Store, in the row of the session id.
    def persist(*fields, store:) = add(Steps::Persist.new(fields.flatten, store))

    # Writes +message+ and sleeps for +seconds+.
    def pause(message, seconds: 1.0) = add(Steps::Pause.new(message, seconds))

    # Calls the block with the context; when it returns falsy, writes
    # +denied+ and ends the flow.
    def gate(denied:, &check) = add(Steps::Gate.new(check, denied))

    # Asks +message+ with a <tt>[yes/no]</tt> prompt. With a block, the
    # steps defined in the block run on yes and the flow goes on either way.
    # Without a block, the flow goes on only on yes. On no, +denied+ is
    # written when given.
    def confirm(message, denied: nil, &) = add(Steps::Confirm.new(message, denied, block_given? ? Flow.steps(&) : nil))

    # A numbered BBS::Selector of the options declared in the block with
    # Steps::Options#option; the option taken runs its steps. With
    # +loop+ the menu comes back after each option until one runs
    # #exit_menu; RUN/STOP, ← or Esc leaves it too. +prompt+ is the
    # menu's status row.
    def menu(prompt, loop: false, &) = add(Steps::Menu.new(prompt, loop, Steps::Options.collect(&)))

    # Leaves the innermost menu; the flow goes on after it.
    def exit_menu = add(Steps::EXIT_MENU)

    # Calls the block with the context and the BBS::FlowRunner. Returning
    # +:halt+ ends the flow; an error is logged and shown to the caller, and
    # the flow goes on.
    def call(&block) = add(Steps::Call.new(block))

    # Runs the windowed BBS::Application +definition+ on the session.
    def app(definition) = add(Steps::App.new(definition))

    private

    def add(step)
      @steps << step
      step
    end
  end
end
