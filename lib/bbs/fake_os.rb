# frozen_string_literal: true

require_relative 'banner'

module BBS
  # A configurable, teletype-style character-mode OS simulator: a scripted
  # boot sequence followed by an interactive command shell. Each simulated OS
  # (MS-DOS, CP/M, an AmigaDOS CLI, …) is just a different Definition — the
  # engine here is generic, so new "operating systems" are added as config,
  # not as new code.
  #
  #   DOS = BBS::FakeOS.define do
  #     name   'MS-DOS'
  #     prompt 'C:\\>'
  #     colors text: "\e[0;37m", accent: "\e[1;32m"
  #
  #     boot do
  #       print 'Award Modular BIOS v4.51PG', delay: 0.4
  #       memtest 16_384
  #       pause 0.5
  #       cls
  #       big_banner 'MS-DOS'
  #     end
  #
  #     ready { puts 'Type HELP for a list of commands.' }
  #
  #     command 'ver'          { |_args, io| io.puts 'MS-DOS Version 6.22' }
  #     command 'cls'          { |_args, io| io.cls }
  #     command 'exit', 'quit' { |_args, io| io.halt }
  #
  #     on_unknown do |input, io|
  #       io.puts "Bad command or file name"
  #     end
  #   end
  #
  #   BBS::FakeOS::Runner.new(session, DOS).run
  #
  # The boot/ready blocks run against a Console (so primitives like `print`,
  # `cls`, `pause`, `banner`, `type` are available without a receiver).
  # Command and on_unknown blocks are called with `(args_or_input, console)` —
  # use the console (`io`) for all output. `on_unknown` is the natural hook for
  # a conversational / LLM-backed shell: anything that is not a registered
  # command lands there.
  module FakeOS
    DEFAULT_COLORS = {
      text:   "\e[0;37m", # light grey on black — the classic console look
      bright: "\e[1;37m",
      accent: "\e[1;32m",
      error:  "\e[1;31m",
      dim:    "\e[1;30m",
      prompt: "\e[0;37m",
    }.freeze

    def self.define(&block)
      definition = Definition.new
      definition.instance_eval(&block)
      definition
    end

    # Immutable-ish description of one simulated OS, built via the define DSL.
    class Definition
      def initialize
        @name        = 'OS'
        @prompt      = '> '
        @colors      = DEFAULT_COLORS.dup
        @boot_block  = nil
        @ready_block = nil
        @commands    = {}
        @order       = []
        @unknown     = nil
      end

      # `name 'MS-DOS'` to set, `name` to read.
      def name(value = nil)
        value.nil? ? @name : (@name = value)
      end

      # Prompt may be a String or a `->(ctx) { ... }` block evaluated per line.
      def prompt(value = nil, &block)
        if block then @prompt = block
        elsif !value.nil? then @prompt = value
        else @prompt
        end
      end

      # Merge SGR overrides, e.g. `colors text: "\e[0;32m"`. Read with no args.
      def colors(overrides = nil)
        overrides ? @colors.merge!(overrides) : @colors
      end

      def boot(&block)  = (@boot_block = block)
      def ready(&block) = (@ready_block = block) # runs once after boot, before the first prompt

      # Register a command under one or more names (the first is the canonical
      # one shown in help). The block receives `(args_string, console)`.
      def command(*names, help: nil, &block)
        primary = names.first.to_s
        @order << primary unless @order.include?(primary)
        names.each do |n|
          @commands[n.to_s.downcase] = { name: primary, help: help, block: block }
        end
      end

      # Fallback for input that matches no command. Block gets `(input, console)`.
      def on_unknown(&block) = (@unknown = block)

      attr_reader :boot_block, :ready_block, :commands, :order, :unknown
    end

    # The live terminal: owns the telnet session and all output primitives, and
    # drives the boot sequence + shell loop. Handlers receive this as `io`.
    class Console
      attr_reader :ctx, :session, :definition

      def initialize(session, definition, context)
        @session    = session
        @definition = definition
        @ctx        = context
        @colors     = definition.colors
        @running    = true
      end

      def run
        instance_eval(&@definition.boot_block)  if @definition.boot_block
        instance_eval(&@definition.ready_block) if @definition.ready_block
        run_shell
      end

      # ── output primitives (also available unqualified inside boot/ready) ─────

      # Write a line (or blank line) terminated by CRLF.
      def puts(text = '', style: :text)
        @session.write("#{color(style)}#{text}#{reset}\r\n")
      end

      # Write text followed by `newline` CRLFs, then sleep `delay` seconds.
      # Handy for boot messages: `print 'POST OK', delay: 0.3`.
      def print(text = '', delay: 0, style: :text, newline: 1)
        @session.write("#{color(style)}#{text}#{reset}#{"\r\n" * newline}")
        sleep_for(delay)
      end

      # Typewriter effect — emit one character at a time at `cps` chars/second.
      def type(text, style: :text, cps: 900, newline: 1)
        delay = cps.positive? ? 1.0 / cps : 0
        @session.write(color(style))
        text.to_s.each_char do |ch|
          @session.write(ch)
          sleep_for(delay)
        end
        @session.write("#{reset}#{"\r\n" * newline}")
      end

      def newline(count = 1) = @session.write("\r\n" * count)

      def cls = @session.write("\e[2J\e[H")

      def pause(seconds) = sleep_for(seconds)

      # Boxed single-line banner (BBS::Banner).
      def banner(text, style: :accent)
        @session.write(Banner.render(text, color: color(style)))
      end

      # Big figlet banner (BBS::Banner / artii).
      def big_banner(text, style: :accent, font: 'standard')
        @session.write(Banner.render_big(text, color: color(style), font: font))
      end

      # The classic counting memory test: `memtest 16_384` →
      # "Memory Test : 16384K OK" counting up in place.
      def memtest(kilobytes, step: 2048, delay: 0.03, label: 'Memory Test : ')
        counted = 0
        while counted < kilobytes
          counted = [counted + step, kilobytes].min
          @session.write("\r#{color(:text)}#{label}#{counted}K #{reset}")
          sleep_for(delay)
        end
        @session.write("#{color(:text)}#{label}#{kilobytes}K OK#{reset}\r\n")
      end

      def cols = (@session.term_cols || 80)
      def rows = (@session.term_rows || 24)

      # Stop the shell loop (used by an `exit`/`quit` command).
      def halt = (@running = false)

      private

      def run_shell
        while @running
          @session.write("#{color(:prompt)}#{resolve_prompt}#{reset}")
          line = @session.readline
          break if line.nil?
          dispatch(line.strip)
        end
      end

      def dispatch(input)
        return if input.empty?
        word, rest = input.split(/\s+/, 2)
        entry = @definition.commands[word.downcase]
        if entry
          entry[:block].call(rest.to_s, self)
        elsif @definition.unknown
          @definition.unknown.call(input, self)
        else
          puts 'Bad command or file name', style: :error
        end
      end

      def resolve_prompt
        prompt = @definition.prompt
        prompt.respond_to?(:call) ? prompt.call(@ctx).to_s : prompt.to_s
      end

      def color(role) = @colors.fetch(role) { @colors[:text] }
      def reset = "\e[0m"
      def sleep_for(seconds) = (sleep(seconds) if seconds&.positive?)
    end

    # Entry point: plays the boot sequence then runs the shell until the user
    # quits or disconnects.
    class Runner
      def initialize(session, definition, context: {})
        @session    = session
        @definition = definition
        @context    = context
      end

      def run
        Console.new(@session, @definition, @context).run
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        nil
      end
    end
  end
end
