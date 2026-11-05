# frozen_string_literal: true

require 'erb'
require 'artii'

module Rubbs
  module Common
    module Call
      # Renders the ERB screens of a flow: <tt><name>.erb</tt> files in a screens
      # directory, evaluated in a Renderer::Context that offers colour and banner
      # helpers.
      class Renderer
        # Reads <tt><name>.erb</tt> from +dir+, evaluates it with +vars+ as
        # instance variables (<tt>{ user: 'x' }</tt> becomes +@user+) and returns
        # the result with every LF turned into CRLF. ERB trim mode <tt>'-'</tt> is
        # on.
        #
        # [name] the screen name, without the +.erb+ extension
        # [vars] Hash of values the template sees as instance variables
        # [dir]  the screens directory; default Rubbs.config.screens_dir
        #
        # Raises RuntimeError when +dir+ is +nil+, and Errno::ENOENT when the
        # file does not exist.
        def self.render(name, vars = {}, dir: Rubbs.config.screens_dir)
          raise 'No screens_dir: set BBS.config.screens_dir or the flow\'s screens_dir' unless dir

          path = File.join(dir, "#{name}.erb")
          ctx  = Context.new(vars)
          ERB.new(File.read(path), trim_mode: '-').result(ctx.ctx_binding).gsub("\n", Modern::Ansi::CRLF)
        end

        # The object an ERB screen is evaluated in. Its methods are the helpers a
        # template can call: colour codes (+green+, +reset+, ...), +clr+,
        # #banner and #big_banner.
        class Context
          # Sets each pair of +vars+ as an instance variable.
          def initialize(vars)
            vars.each { |k, v| instance_variable_set(:"@#{k}", v) }
          end

          # The Binding ERB evaluates the template in.
          def ctx_binding = binding

          # Returns +text+ in a bright green double-line box with +padding+
          # spaces on each side, as three LF-separated lines.
          def banner(text, padding: 2)
            inner = "#{' ' * padding}#{text}#{' ' * padding}"
            bar   = '═' * inner.length
            "#{green}╔#{bar}╗#{reset}\n" \
              "#{green}║#{inner}║#{reset}\n" \
              "#{green}╚#{bar}╝#{reset}"
          end

          # Returns +text+ as large Artii letters in +font+ (default
          # <tt>'slant'</tt>), each line indented by two spaces and bright green,
          # LF-separated.
          def big_banner(text, font: 'slant')
            Artii::Base.new(font: font).asciify(text)
              .split("\n")
              .map { |l| "  #{green}#{l}#{reset}" }
              .join("\n")
          end

          # Escape sequence that clears the screen and homes the cursor.
          def clr       = Modern::Ansi::CLEAR
          # Escape sequence that resets all colours and attributes.
          def reset     = Modern::Ansi::RESET
          # Escape sequence for bright green text.
          def green     = Modern::Ansi::BRIGHT_GREEN
          # Escape sequence for bright yellow text.
          def yellow    = Modern::Ansi::BRIGHT_YELLOW
          # Escape sequence for bright cyan text.
          def cyan      = Modern::Ansi::BRIGHT_CYAN
          # Escape sequence for bright white text.
          def white     = Modern::Ansi::WHITE
          # Escape sequence for light gray text.
          def gray      = Modern::Ansi::GREY
          # Escape sequence for bright red text.
          def red       = Modern::Ansi::BRIGHT_RED
          # Escape sequence for normal (dim) green text.
          def dim_green = Modern::Ansi::GREEN
        end
      end
    end
  end
end
