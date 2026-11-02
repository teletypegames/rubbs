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
          runner.line('Something went wrong.', style: :error)
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
    end
  end
end

require_relative 'questions'
