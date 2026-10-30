# frozen_string_literal: true

module BBS
  # Named ANSI colours for plain line output. Include or call directly:
  #
  #   BBS::Color.c(:yellow, 'Welcome')   # => "\e[0;33mWelcome\e[0m"
  module Color
    # The colour names and their ANSI SGR escape sequences, plus +:reset+.
    COLORS = {
      reset: Ansi::RESET,        gray:    Ansi::GREY,    yellow: Ansi::YELLOW,
      white: Ansi::WHITE,        blue:    Ansi::BLUE,    cyan:   Ansi::CYAN,
      green: Ansi::BRIGHT_GREEN, magenta: Ansi::MAGENTA, red:    Ansi::BRIGHT_RED
    }.freeze

    module_function

    # Returns +text+ wrapped in the escape sequence of +color+ (a key of
    # COLORS) and a reset. Raises KeyError for an unknown colour name.
    def c(color, text)
      "#{COLORS.fetch(color)}#{text}#{COLORS[:reset]}"
    end
  end
end
