# frozen_string_literal: true

module Rubbs
  module Common
    module FakeOS
      # The live terminal: owns the telnet session and all output primitives, and
      # drives the boot sequence + shell loop. Handlers receive this as +io+.
      class Console
        # The context Hash, the Rubbs::Common::Line::Session, and the Definition being run.
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
          @session.write("#{color(style)}#{text}#{reset}#{Modern::Ansi::CRLF}")
        end

        # Writes +text+ in +style+ followed by +newline+ CRLFs, then sleeps
        # +delay+ seconds. Handy for boot messages:
        # <tt>print 'POST OK', delay: 0.3</tt>.
        def print(text = '', delay: 0, style: :text, newline: 1)
          @session.write("#{color(style)}#{text}#{reset}#{Modern::Ansi::CRLF * newline}")
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
          @session.write("#{reset}#{Modern::Ansi::CRLF * newline}")
        end

        # Writes +count+ CRLFs.
        def newline(count = 1) = @session.write(Modern::Ansi::CRLF * count)

        # Resets the colours and clears the screen, cursor to the top left.
        def cls = @session.write("#{reset}#{Modern::Ansi::CLEAR}")

        # Sleeps for +seconds+ (nothing for zero or +nil+).
        def pause(seconds) = sleep_for(seconds)

        # Writes +text+ in a boxed single-line banner (Rubbs::Common::Text::Banner.render) in
        # the colour role +style+.
        def banner(text, style: :accent)
          @session.write(Text::Banner.render(text, color: color(style)))
        end

        # Writes +text+ as big FIGlet letters in +font+ (Rubbs::Common::Text::Banner.render_big)
        # in the colour role +style+.
        def big_banner(text, style: :accent, font: 'standard')
          @session.write(Text::Banner.render_big(text, color: color(style), font: font))
        end

        # The classic counting memory test: <tt>memtest 16_384</tt> writes
        # "Memory Test : 16384K OK", counting up in place by +step+ kilobytes
        # every +delay+ seconds.
        def memtest(kilobytes, step: 2048, delay: 0.03, label: 'Memory Test : ')
          counted = 0
          while counted < kilobytes
            counted = [counted + step, kilobytes].min
            @session.write("#{Modern::Ansi::CR}#{color(:text)}#{label}#{counted}K #{reset}")
            sleep_for(delay)
          end
          @session.write("#{color(:text)}#{label}#{kilobytes}K OK#{reset}#{Modern::Ansi::CRLF}")
        end

        # The terminal width in columns; 80 when the terminal did not report it.
        def cols = @session.term_cols || Line::Telnet::DEFAULT_COLS
        # The terminal height in rows; 24 when the terminal did not report it.
        def rows = @session.term_rows || Line::Telnet::DEFAULT_ROWS

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

          word, rest = input.split(Text::Patterns::WHITESPACE, 2)
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
          Rubbs.log('fake os command', e)
          puts "Error: #{e.message}", style: :error
        end

        def resolve_prompt
          prompt = @definition.prompt
          prompt.respond_to?(:call) ? prompt.call(@ctx).to_s : prompt.to_s
        end

        def color(role) = @colors.fetch(role) { @colors[:text] }
        def reset = "#{Modern::Ansi::RESET}#{@colors[:base]}"
        def sleep_for(seconds) = (sleep(seconds) if seconds&.positive?)
      end
    end
  end
end
