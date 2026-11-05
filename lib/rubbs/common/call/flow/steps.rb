# frozen_string_literal: true

module Rubbs
  module Common
    module Call
      class Flow
        # The steps of a Flow. Each one is a small object with
        # <tt>run(runner)</tt>, which does its part on the Rubbs::Common::Call::FlowRunner and
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
              runner.write Common::Text::Banner.render(text, color: runner.color(style))
              nil
            end
          end

          # +text+ in large FIGlet letters of +font+ in the colour of +style+.
          BigBanner = Struct.new(:text, :style, :font) do
            # Writes the letters. Returns +nil+.
            def run(runner)
              runner.write Common::Text::Banner.render_big(text, color: runner.color(style), font: font)
              nil
            end
          end

          # An indented paragraph with a blank line around it.
          Say = Struct.new(:text, :style) do
            # Writes the paragraph. Returns +nil+.
            def run(runner)
              runner.write Modern::Ansi::CRLF
              runner.line(text, style: style)
              runner.write Modern::Ansi::CRLF
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
              runner.write Modern::Ansi::CRLF
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

          # The login at the start of a call (Flow#login).
          class Login
            # Runs Rubbs::Common::Auth::Login#at_call on the runner's line. Returns
            # +:halt+ when the caller may not come in or hung up, else +nil+.
            def run(runner)
              setup = Rubbs.config.auth or return nil
              tell  = ->(text) { runner.line(text, style: :error) }
              ask   = ->(label, mask: nil) { runner.ask("  #{label}: ", mask: mask) }
              Auth::Login.new(setup, runner.session, ask: ask, tell: tell).at_call == :halt ? :halt : nil
            rescue *Line::LINE_DROPPED
              :halt
            end
          end

          # A block called with the context and the runner.
          Call = Struct.new(:block) do
            # Runs the block in +runner+: +:halt+ when it says so or the line
            # drops, +nil+ otherwise; an error is logged and shown to the caller.
            def run(runner)
              runner.instance_exec(&block) == :halt ? :halt : nil
            rescue *Line::LINE_DROPPED
              :halt
            rescue StandardError => e
              Rubbs.log('flow call', e)
              runner.write Modern::Ansi::CRLF
              runner.line('Something went wrong.', style: :error)
              nil
            end
          end

          # A windowed Rubbs::Modern::Application.
          App = Struct.new(:definition) do
            # Runs the application. Returns +:halt+ when the line drops, +nil+
            # otherwise.
            def run(runner)
              definition.run(session: runner.session, session_id: runner.session_id, context: runner.context)
              nil
            rescue *Line::LINE_DROPPED
              :halt
            end
          end

          # A Rubbs::Petscii::Face run on the line.
          Face = Struct.new(:face) do
            # Runs a new +face+ with the session, the context and the board.
            # Returns +:halt+ when the line drops, +nil+ otherwise; an error is
            # logged and the caller told.
            def run(runner)
              face.new(runner.session, runner.context, Rubbs.config.board).run
              nil
            rescue *Line::LINE_DROPPED
              :halt
            rescue StandardError => e
              Rubbs.log('face', e)
              nil
            end
          end

          # The goodbye screen (Rubbs::Common::Call::Goodbye.show): its +note+ (a String or a
          # callable given the context and the session) and its +options+.
          Goodbye = Struct.new(:note, :options) do
            # Shows it. Returns +:halt+: nothing comes after a goodbye.
            def run(runner)
              text = note.respond_to?(:call) ? note.call(runner.context, runner.session) : note
              Common::Call::Goodbye.show(runner.session, note: text, **(options || {}))
              :halt
            end
          end

          # Another Rubbs::Common::Call::Flow run in a runner of its own.
          Nested = Struct.new(:flow) do
            # Runs it with the session and the context. Returns +nil+: what
            # comes after it (a goodbye on a line that has dropped) goes quietly.
            def run(runner)
              FlowRunner.new(runner.session, runner.session_id, flow, context: runner.context).run
              nil
            end
          end
        end
      end
    end
  end
end

require_relative 'questions'
