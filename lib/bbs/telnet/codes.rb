# frozen_string_literal: true

module BBS
  module Telnet
    # The telnet command bytes and option codes, for every class that
    # speaks telnet (BBS::Telnet, Telnet::Parser, the Gateway's link).
    module Codes
      # Telnet "interpret as command" byte, the start of every telnet command.
      IAC  = 255
      # Telnet WILL: the sender offers to use an option.
      WILL = 251
      # Telnet WONT: the sender refuses an option.
      WONT = 252
      # Telnet DO: the sender asks the other side to use an option.
      DO   = 253
      # Telnet DONT: the sender asks the other side not to use an option.
      DONT = 254
      # Telnet SB: start of a subnegotiation.
      SB   = 250
      # Telnet SE: end of a subnegotiation.
      SE   = 240

      # Telnet option BINARY (8-bit data, no CR NUL handling), asked for by
      # the file transfers.
      BINARY_OPT = 0
      # Telnet option ECHO (the server echoes what the caller types).
      ECHO_OPT = 1
      # Telnet option SUPPRESS-GO-AHEAD (character-at-a-time mode).
      SGA_OPT  = 3
      # Telnet option NAWS (the client reports its window size).
      NAWS_OPT = 31
      # Telnet option NEW-ENVIRON (RFC 1572: the client sends variables).
      NEW_ENVIRON_OPT = 39
    end
  end
end
