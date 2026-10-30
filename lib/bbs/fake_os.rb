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
  # The boot/ready blocks run against a Console (so primitives like +print+,
  # +cls+, +pause+, +banner+, +type+ are available without a receiver).
  # Command and on_unknown blocks are called with
  # <tt>(args_or_input, console)</tt>; use the console (+io+) for all output.
  # +on_unknown+ is the natural hook for a conversational / LLM-backed shell:
  # anything that is not a registered command lands there.
  module FakeOS
    # The default SGR sequence for each colour role a Console uses: +text+,
    # +bright+, +accent+, +error+, +dim+, +prompt+, and +base+, which every
    # reset returns to.
    DEFAULT_COLORS = {
      text:   Ansi::GREY, # light grey on black — the classic console look
      bright: Ansi::WHITE,
      accent: Ansi::BRIGHT_GREEN,
      error:  Ansi::BRIGHT_RED,
      dim:    Ansi::DARK_GREY,
      prompt: Ansi::GREY,
      base:   '', # what every reset returns to: a background here colours the whole screen
    }.freeze

    # Builds a Definition by evaluating the block in a new one.
    #
    # Returns the Definition.
    def self.define(&block)
      definition = Definition.new
      definition.instance_eval(&block)
      definition
    end

    # Immutable-ish description of one simulated OS, built via the define DSL.
    class Definition
      # Creates a definition named +OS+ with a <tt>'> '</tt> prompt, the
      # DEFAULT_COLORS, and no boot, ready or commands.
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

      # Sets the OS name with an argument (<tt>name 'MS-DOS'</tt>); returns
      # it without one.
      def name(value = nil)
        value.nil? ? @name : (@name = value)
      end

      # Sets the shell prompt with a String argument, or with a block called
      # with the context before each line; returns it with neither.
      def prompt(value = nil, &block)
        if block then @prompt = block
        elsif !value.nil? then @prompt = value
        else @prompt
        end
      end

      # Merges SGR overrides into the colour roles, e.g.
      # <tt>colors text: "\e[0;32m"</tt>. Returns the colour Hash with no
      # argument.
      def colors(overrides = nil)
        overrides ? @colors.merge!(overrides) : @colors
      end

      # Sets the boot sequence, run in the Console before anything else.
      def boot(&block)  = (@boot_block = block)
      # Sets the block run in the Console once after boot, before the first
      # prompt.
      def ready(&block) = (@ready_block = block) # runs once after boot, before the first prompt

      # Registers a command under one or more names (the first is the
      # canonical one shown in help); names match case-insensitively. The
      # block receives <tt>(args_string, console)</tt>. +help+ is an optional
      # description stored with the command.
      def command(*names, help: nil, &block)
        primary = names.first.to_s
        @order << primary unless @order.include?(primary)
        names.each do |n|
          @commands[n.to_s.downcase] = { name: primary, help: help, block: block }
        end
      end

      # Sets the fallback for input that matches no command. The block gets
      # <tt>(input, console)</tt>. Without one, the shell prints "Bad command
      # or file name".
      def on_unknown(&block) = (@unknown = block)

      # The boot and ready blocks, the commands (a Hash of lower-case name to
      # a Hash with +:name+, +:help+ and +:block+), the canonical command
      # names in registration order, and the on_unknown block.
      attr_reader :boot_block, :ready_block, :commands, :order, :unknown
    end

    # The live terminal: owns the telnet session and all output primitives, and
    # drives the boot sequence + shell loop. Handlers receive this as +io+.
    class Console
      # The context Hash, the BBS::Session, and the Definition being run.
      attr_reader :ctx, :session, :definition

      # Creates a console running +definition+ on +session+ with the context
      # Hash +context+.
      def initialize(session, definition, context)
        @session    = session
        @definition = definition
        @ctx        = context
        @colors     = definition.colors
        @running    = true
      end

      # Runs the boot block, the ready block, then the shell: prints the
      # prompt, reads a line, and runs the matching command or the
      # on_unknown block, until #halt is called or the line drops. An error
      # raised by a command is logged and printed; IOError and
      # SystemCallError are re-raised.
      def run
        instance_eval(&@definition.boot_block)  if @definition.boot_block
        instance_eval(&@definition.ready_block) if @definition.ready_block
        run_shell
      end

      # ── output primitives (also available unqualified inside boot/ready) ─────

      # Writes +text+ (or a blank line) in the colour role +style+, followed
      # by CRLF.
      def puts(text = '', style: :text)
        @session.write("#{color(style)}#{text}#{reset}#{Ansi::CRLF}")
      end

      # Writes +text+ in +style+ followed by +newline+ CRLFs, then sleeps
      # +delay+ seconds. Handy for boot messages:
      # <tt>print 'POST OK', delay: 0.3</tt>.
      def print(text = '', delay: 0, style: :text, newline: 1)
        @session.write("#{color(style)}#{text}#{reset}#{Ansi::CRLF * newline}")
        sleep_for(delay)
      end

      # Typewriter effect: writes +text+ one character at a time at +cps+
      # characters a second, then +newline+ CRLFs.
      def type(text, style: :text, cps: 900, newline: 1)
        delay = cps.positive? ? 1.0 / cps : 0
        @session.write(color(style))
        text.to_s.each_char do |ch|
          @session.write(ch)
          sleep_for(delay)
        end
        @session.write("#{reset}#{Ansi::CRLF * newline}")
      end

      # Writes +count+ CRLFs.
      def newline(count = 1) = @session.write(Ansi::CRLF * count)

      # Resets the colours and clears the screen, cursor to the top left.
      def cls = @session.write("#{reset}#{Ansi::CLEAR}")

      # Sleeps for +seconds+ (nothing for zero or +nil+).
      def pause(seconds) = sleep_for(seconds)

      # Writes +text+ in a boxed single-line banner (BBS::Banner.render) in
      # the colour role +style+.
      def banner(text, style: :accent)
        @session.write(Banner.render(text, color: color(style)))
      end

      # Writes +text+ as big FIGlet letters in +font+ (BBS::Banner.render_big)
      # in the colour role +style+.
      def big_banner(text, style: :accent, font: 'standard')
        @session.write(Banner.render_big(text, color: color(style), font: font))
      end

      # The classic counting memory test: <tt>memtest 16_384</tt> writes
      # "Memory Test : 16384K OK", counting up in place by +step+ kilobytes
      # every +delay+ seconds.
      def memtest(kilobytes, step: 2048, delay: 0.03, label: 'Memory Test : ')
        counted = 0
        while counted < kilobytes
          counted = [counted + step, kilobytes].min
          @session.write("#{Ansi::CR}#{color(:text)}#{label}#{counted}K #{reset}")
          sleep_for(delay)
        end
        @session.write("#{color(:text)}#{label}#{kilobytes}K OK#{reset}#{Ansi::CRLF}")
      end

      # The terminal width in columns; 80 when the terminal did not report it.
      def cols = (@session.term_cols || 80)
      # The terminal height in rows; 24 when the terminal did not report it.
      def rows = (@session.term_rows || 24)

      # Stops the shell loop after the current command (used by an
      # +exit+/+quit+ command).
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
        word, rest = input.split(Patterns::WHITESPACE, 2)
        entry = @definition.commands[word.downcase]
        if entry
          entry[:block].call(rest.to_s, self)
        elsif @definition.unknown
          @definition.unknown.call(input, self)
        else
          puts 'Bad command or file name', style: :error
        end
      rescue IOError, SystemCallError
        raise
      rescue StandardError => e
        warn "FakeOS command error: #{e.class}: #{e.message}"
        puts "Error: #{e.message}", style: :error
      end

      def resolve_prompt
        prompt = @definition.prompt
        prompt.respond_to?(:call) ? prompt.call(@ctx).to_s : prompt.to_s
      end

      def color(role) = @colors.fetch(role) { @colors[:text] }
      def reset = "#{Ansi::RESET}#{@colors[:base]}"
      def sleep_for(seconds) = (sleep(seconds) if seconds&.positive?)
    end

    # Entry point: plays the boot sequence then runs the shell until the user
    # quits or disconnects.
    class Runner
      # Creates a runner for +definition+ on +session+; +context+ is passed to
      # the Console.
      def initialize(session, definition, context: {})
        @session    = session
        @definition = definition
        @context    = context
      end

      # Runs a new Console. A dropped line ends it quietly.
      #
      # Returns +nil+ when the line dropped.
      def run
        Console.new(@session, @definition, @context).run
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        nil
      end
    end
  end
end
