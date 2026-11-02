# frozen_string_literal: true

module BBS
  class Flow
    # The steps of a Flow. Each one is a small object with
    # <tt>run(runner)</tt>, which does its part on the BBS::FlowRunner and
    # returns +nil+ to go on, +:halt+ to end the flow, or +:exit_menu+ to
    # leave the innermost menu.
    module Steps
      # Renders the ERB screen +name+ with the context and +vars+.
      Screen = Struct.new(:name, :vars) do
        # Writes the rendered screen. Returns +nil+.
        def run(runner)
          vars = self.vars.transform_values { |v| v.is_a?(Symbol) ? runner.context[v] : v }
          runner.write Renderer.render(name.to_s, runner.context.merge(vars), dir: runner.screens_dir)
          nil
        end
      end

      # A boxed banner of +text+ in the colour of +style+.
      Banner = Struct.new(:text, :style) do
        # Writes the banner. Returns +nil+.
        def run(runner)
          runner.write BBS::Banner.render(text, color: runner.color(style))
          nil
        end
      end

      # +text+ in large FIGlet letters of +font+ in the colour of +style+.
      BigBanner = Struct.new(:text, :style, :font) do
        # Writes the letters. Returns +nil+.
        def run(runner)
          runner.write BBS::Banner.render_big(text, color: runner.color(style), font: font)
          nil
        end
      end

      # An indented paragraph with a blank line around it.
      Say = Struct.new(:text, :style) do
        # Writes the paragraph. Returns +nil+.
        def run(runner)
          runner.write Ansi::CRLF
          runner.line(text, style: style)
          runner.write Ansi::CRLF
          nil
        end
      end

      # One indented line: +content+, or what +block+ returns for the
      # context.
      Text = Struct.new(:content, :block, :style) do
        # Writes the line unless it is +nil+. Returns +nil+.
        def run(runner)
          text = block ? block.call(runner.context) : content
          runner.line(text, style: style) if text
          nil
        end
      end

      # A question whose answer goes into the context under +name+.
      Ask = Struct.new(:name, :prompt, :transform, :validate) do
        # Reads the answer: +:halt+ when the caller hangs up or the answer
        # is refused, +nil+ otherwise.
        def run(runner)
          value = runner.ask("  #{runner.color(:prompt)}#{prompt}#{Ansi::RESET}: ")
          return :halt if value.nil?

          value = Steps.transform(value, transform)
          return refuse(runner) unless Steps.valid?(value, validate)

          runner.context[name] = value
          nil
        end

        private

        def refuse(runner)
          message = validate == :email ? "That doesn't look like a valid email address." : 'Invalid input.'
          runner.write Ansi::CRLF
          runner.line("#{message} Farewell.", style: :error)
          runner.write Ansi::CRLF
          :halt
        end
      end

      # Saves the context values of +fields+ to +store+ in the session's
      # row.
      Persist = Struct.new(:fields, :store) do
        # Upserts the fields present in the context. Returns +nil+.
        def run(runner)
          values = fields.filter_map { |f| [f, runner.context[f]] if runner.context.key?(f) }.to_h
          store.upsert(session_id: runner.session_id, **values) unless values.empty?
          nil
        end
      end

      # +message+, then a wait of +seconds+.
      Pause = Struct.new(:message, :seconds) do
        # Writes the message and sleeps. Returns +nil+.
        def run(runner)
          runner.write Ansi::CRLF
          runner.line(message, style: :info)
          sleep seconds
          nil
        end
      end

      # A check of the context; +denied+ and the end of the flow when it
      # fails.
      Gate = Struct.new(:check, :denied) do
        # Returns +nil+ when the check passes, +:halt+ after +denied+
        # otherwise.
        def run(runner)
          return nil if check.call(runner.context)

          runner.line(denied, style: :error)
          runner.write Ansi::CRLF
          :halt
        end
      end

      # A yes/no question. With +steps+ they run on yes and the flow goes
      # on either way; without, the flow goes on only on yes.
      Confirm = Struct.new(:message, :denied, :steps) do
        # Asks; returns what the steps return on yes, +:halt+ on a hang-up
        # or on no without steps, +nil+ otherwise.
        def run(runner)
          answer = runner.ask("#{Ansi::CRLF}  #{runner.color(:prompt)}#{message}#{Ansi::RESET} [yes/no]: ")
          return :halt if answer.nil?
          return steps ? runner.execute(steps) : nil if %w[yes y].include?(answer.downcase)

          deny(runner)
        end

        private

        def deny(runner)
          if denied
            runner.write Ansi::CRLF
            runner.line(denied, style: :muted)
            runner.write Ansi::CRLF
          end
          steps ? nil : :halt
        end
      end

      # A numbered menu of +options+ (pairs of label and steps).
      Menu = Struct.new(:prompt, :repeat, :options) do
        # Shows the menu until an option leaves it. Returns +:halt+ when
        # the flow ends inside it, +nil+ otherwise.
        def run(runner)
          loop do
            steps = runner.select(options, hint: prompt)
            return nil if steps.nil?

            result = runner.execute(steps)
            return :halt if result == :halt
            return nil if result == :exit_menu || !repeat
          end
        end
      end

      # The receiver of a Flow#menu block.
      class Options
        # The options of the block: an Array of <tt>[label, steps]</tt>.
        def self.collect(&)
          options = new
          options.instance_eval(&)
          options.list
        end

        # The options so far.
        attr_reader :list

        # Creates an empty list.
        def initialize
          @list = []
        end

        # Adds an option labelled +label+ whose steps are those of the
        # block.
        def option(label, &) = @list << [label, Flow.steps(&)]
      end

      # Leaves the innermost menu.
      class ExitMenu
        # Returns +:exit_menu+.
        def run(_runner) = :exit_menu
      end

      # The one ExitMenu step.
      EXIT_MENU = ExitMenu.new.freeze

      # A block called with the context and the runner.
      Call = Struct.new(:block) do
        # Calls the block: +:halt+ when it says so or the line drops, +nil+
        # otherwise; an error is logged and shown to the caller.
        def run(runner)
          block.call(runner.context, runner) == :halt ? :halt : nil
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          :halt
        rescue StandardError => e
          warn "BBS call error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          runner.write Ansi::CRLF
          runner.line("Something went wrong.", style: :error)
          nil
        end
      end

      # A windowed BBS::Application.
      App = Struct.new(:definition) do
        # Runs the application. Returns +:halt+ when the line drops, +nil+
        # otherwise.
        def run(runner)
          definition.run(session: runner.session, session_id: runner.session_id, context: runner.context)
          nil
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          :halt
        end
      end

      # An address the +:email+ validator accepts: something, an @, and a
      # domain with a dot.
      EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      # +value+ after +transform+: +:upcase+, +:downcase+, a Proc, or
      # +nil+ for none.
      def self.transform(value, transform)
        case transform
        when :upcase, :downcase then value.public_send(transform)
        when Proc then transform.call(value)
        else value
        end
      end

      # Whether +value+ passes +validate+: +:email+, +:non_empty+, a Proc
      # or Method, or +nil+ for anything.
      def self.valid?(value, validate)
        case validate
        when :email then value.match?(EMAIL)
        when :non_empty then !value.empty?
        when Proc, Method then validate.call(value) ? true : false
        else true
        end
      end
    end
  end
end
