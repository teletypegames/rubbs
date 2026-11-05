# frozen_string_literal: true

module Rubbs
  module Common
    module Call
      class Flow
        # The steps of a Flow that ask the caller and act on the answer (see
        # Flow::Steps for the rest).
        module Steps
          # A question whose answer goes into the context under +name+.
          Ask = Struct.new(:name, :prompt, :transform, :validate) do
            # Reads the answer: +:halt+ when the caller hangs up or the answer
            # is refused, +nil+ otherwise.
            def run(runner)
              value = runner.ask("  #{runner.color(:prompt)}#{prompt}#{Modern::Ansi::RESET}: ")
              return :halt if value.nil?

              value = Steps.transform(value, transform)
              return refuse(runner) unless Steps.valid?(value, validate)

              runner.context[name] = value
              nil
            end

            private

            def refuse(runner)
              message = validate == :email ? "That doesn't look like a valid email address." : 'Invalid input.'
              runner.write Modern::Ansi::CRLF
              runner.line("#{message} Farewell.", style: :error)
              runner.write Modern::Ansi::CRLF
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

          # A check of the context; +denied+ and the end of the flow when it
          # fails.
          Gate = Struct.new(:check, :denied) do
            # Returns +nil+ when the check passes, +:halt+ after +denied+
            # otherwise.
            def run(runner)
              return nil if check.call(runner.context)

              runner.line(denied, style: :error)
              runner.write Modern::Ansi::CRLF
              :halt
            end
          end

          # A yes/no question. With +steps+ they run on yes and the flow goes
          # on either way; without, the flow goes on only on yes.
          Confirm = Struct.new(:message, :denied, :steps) do
            # Asks; returns what the steps return on yes, +:halt+ on a hang-up
            # or on no without steps, +nil+ otherwise.
            def run(runner)
              answer = runner.ask("#{Modern::Ansi::CRLF}  #{runner.color(:prompt)}#{message}#{Modern::Ansi::RESET} [yes/no]: ")
              return :halt if answer.nil?
              return steps ? runner.execute(steps) : nil if %w[yes y].include?(answer.downcase)

              deny(runner)
            end

            private

            def deny(runner)
              if denied
                runner.write Modern::Ansi::CRLF
                runner.line(denied, style: :muted)
                runner.write Modern::Ansi::CRLF
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
  end
end
