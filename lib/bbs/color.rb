# frozen_string_literal: true

module BBS
  module Color
    COLORS = {
      reset: "\e[0m",    gray:    "\e[0;37m", yellow:  "\e[0;33m",
      white: "\e[1;37m", blue:    "\e[0;34m", cyan:    "\e[0;36m",
      green: "\e[1;32m", magenta: "\e[0;35m", red:     "\e[1;31m"
    }.freeze

    module_function

    def c(color, text)
      "#{COLORS.fetch(color)}#{text}#{COLORS[:reset]}"
    end
  end
end
