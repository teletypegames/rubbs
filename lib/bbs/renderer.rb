# frozen_string_literal: true

require 'erb'
require 'artii'

module BBS
  class Renderer
    def self.render(name, vars = {})
      dir  = BBS.config.screens_dir or raise "BBS.config.screens_dir is not set"
      path = File.join(dir, "#{name}.erb")
      ctx  = Context.new(vars)
      ERB.new(File.read(path), trim_mode: '-').result(ctx.ctx_binding).gsub("\n", "\r\n")
    end

    class Context
      def initialize(vars)
        vars.each { |k, v| instance_variable_set(:"@#{k}", v) }
      end

      def ctx_binding = binding

      def banner(text, padding: 2)
        inner = "#{' ' * padding}#{text}#{' ' * padding}"
        bar   = '═' * inner.length
        "#{green}╔#{bar}╗#{reset}\n" \
        "#{green}║#{inner}║#{reset}\n" \
        "#{green}╚#{bar}╝#{reset}"
      end

      def big_banner(text, font: 'slant')
        Artii::Base.new(font: font).asciify(text)
          .split("\n")
          .map { |l| "  #{green}#{l}#{reset}" }
          .join("\n")
      end

      def clr       = "\e[2J\e[H"
      def reset     = "\e[0m"
      def green     = "\e[1;32m"
      def yellow    = "\e[1;33m"
      def cyan      = "\e[1;36m"
      def white     = "\e[1;37m"
      def gray      = "\e[0;37m"
      def red       = "\e[1;31m"
      def dim_green = "\e[0;32m"
    end
  end
end
