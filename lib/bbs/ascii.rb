# frozen_string_literal: true

module BBS
  # The ASCII control bytes a terminal sends and the board reads, as
  # Integers, in one place for the telnet line, the PETSCII encoder and the
  # file transfers.
  module Ascii
    # NUL: the byte a telnet client may send after a carriage return.
    NUL = 0x00
    # NUL as a one-character String.
    NUL_CHAR = "\0"
    # End of text: Ctrl-C.
    ETX = 0x03
    # Backspace: Ctrl-H.
    BS = 0x08
    # Horizontal tab.
    TAB = 0x09
    # Line feed.
    LF = 0x0a
    # Form feed: Ctrl-L.
    FF = 0x0c
    # Carriage return: the ENTER key.
    CR = 0x0d
    # Escape.
    ESC = 0x1b
    # Space, the first printable character.
    SPACE = 0x20
    # The printable characters, space to tilde.
    PRINTABLE = SPACE..0x7e
    # Delete: the backspace key of many terminals.
    DEL = 0x7f
  end
end
