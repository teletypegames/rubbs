# frozen_string_literal: true

module BBS
  # Named ANSI colours for plain line output. Include or call directly:
  #
  #   BBS::Color.c(:yellow, 'Welcome')   # => "\e[0;33mWelcome\e[0m"
  module Color
    # The colour names and their ANSI SGR escape sequences, plus +:reset+.
    COLORS = {
      reset: "\e[0m",    gray:    "\e[0;37m", yellow:  "\e[0;33m",
      white: "\e[1;37m", blue:    "\e[0;34m", cyan:    "\e[0;36m",
      green: "\e[1;32m", magenta: "\e[0;35m", red:     "\e[1;31m"
    }.freeze

    module_function

    # Returns +text+ wrapped in the escape sequence of +color+ (a key of
    # COLORS) and a reset. Raises KeyError for an unknown colour name.
    def c(color, text)
      "#{COLORS.fetch(color)}#{text}#{COLORS[:reset]}"
    end
  end
end
