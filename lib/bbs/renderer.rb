# frozen_string_literal: true

require 'erb'
require 'artii'

module BBS
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
    # [dir]  the screens directory; default BBS.config.screens_dir
    #
    # Raises RuntimeError when +dir+ is +nil+, and Errno::ENOENT when the
    # file does not exist.
    def self.render(name, vars = {}, dir: BBS.config.screens_dir)
      raise 'No screens_dir: set BBS.config.screens_dir or the flow\'s screens_dir' unless dir
      path = File.join(dir, "#{name}.erb")
      ctx  = Context.new(vars)
      ERB.new(File.read(path), trim_mode: '-').result(ctx.ctx_binding).gsub("\n", "\r\n")
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
      def clr       = "\e[2J\e[H"
      # Escape sequence that resets all colours and attributes.
      def reset     = "\e[0m"
      # Escape sequence for bright green text.
      def green     = "\e[1;32m"
      # Escape sequence for bright yellow text.
      def yellow    = "\e[1;33m"
      # Escape sequence for bright cyan text.
      def cyan      = "\e[1;36m"
      # Escape sequence for bright white text.
      def white     = "\e[1;37m"
      # Escape sequence for light gray text.
      def gray      = "\e[0;37m"
      # Escape sequence for bright red text.
      def red       = "\e[1;31m"
      # Escape sequence for normal (dim) green text.
      def dim_green = "\e[0;32m"
    end
  end
end
