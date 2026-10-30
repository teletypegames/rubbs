# frozen_string_literal: true

module BBS
  # The ANSI escape sequences and line ends a board writes to the caller's
  # terminal, and the patterns that find escape sequences in text, in one
  # place for every class that writes or measures ANSI text.
  #
  #   session.write("#{BBS::Ansi::CLEAR}#{BBS::Ansi::BRIGHT_GREEN}Hi#{BBS::Ansi::RESET}#{BBS::Ansi::CRLF}")
  module Ansi
    # Line end on the telnet line: carriage return and line feed.
    CRLF = "\r\n"
    # Carriage return alone: back to the start of the line.
    CR = "\r"
    # The escape character that starts every sequence.
    ESC = "\e"
    # Control Sequence Introducer: ESC and a left bracket.
    CSI = "\e["
    # The byte after ESC that makes a CSI sequence.
    CSI_BYTE = '['
    # SGR reset: default colours and attributes.
    RESET = "\e[0m"
    # Erases the whole screen; the cursor stays where it is.
    CLEAR_SCREEN = "\e[2J"
    # Moves the cursor to the top left corner.
    CURSOR_HOME = "\e[H"
    # Erases the screen and moves the cursor to the top left corner.
    CLEAR = "#{CLEAR_SCREEN}#{CURSOR_HOME}".freeze
    # Hides the cursor.
    HIDE_CURSOR = "\e[?25l"
    # Shows the cursor.
    SHOW_CURSOR = "\e[?25h"
    # SGR: black background.
    BG_BLACK = "\e[40m"

    # SGR: dark grey (bold black) text.
    DARK_GREY = "\e[1;30m"
    # SGR: grey (normal white) text.
    GREY = "\e[0;37m"
    # SGR: bright white text.
    WHITE = "\e[1;37m"
    # SGR: bright red text.
    BRIGHT_RED = "\e[1;31m"
    # SGR: green text.
    GREEN = "\e[0;32m"
    # SGR: bright green text.
    BRIGHT_GREEN = "\e[1;32m"
    # SGR: yellow (brown) text.
    YELLOW = "\e[0;33m"
    # SGR: bright yellow text.
    BRIGHT_YELLOW = "\e[1;33m"
    # SGR: blue text.
    BLUE = "\e[0;34m"
    # SGR: magenta text.
    MAGENTA = "\e[0;35m"
    # SGR: cyan text.
    CYAN = "\e[0;36m"
    # SGR: bright cyan text.
    BRIGHT_CYAN = "\e[1;36m"

    # A CSI sequence with digit and semicolon parameters and a letter or
    # <tt>~</tt> final byte.
    CSI_RE = /\e\[[\d;]*[A-Za-z~]/
    # The final byte of a CSI sequence: a letter or <tt>~</tt>.
    CSI_FINAL = /[A-Za-z~]/
    # A letter, the final byte of a CSI sequence that ends with one.
    CSI_LETTER = /[A-Za-z]/
    # The most parameter bytes read before a CSI sequence is given up.
    MAX_CSI_LENGTH = 32
  end
end
