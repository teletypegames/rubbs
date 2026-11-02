# frozen_string_literal: true

module BBS
  module Petscii
    # The colours of a line-by-line C64 board as two-letter constants: the
    # C64 names of the BBS::Ansi palette, so each is an ANSI SGR sequence. A
    # PETSCII session (<tt>session.petscii!</tt>) turns them into the C64's
    # own colour codes, and the width helpers of rubbs (BBS::FrameBuffer)
    # know ANSI, where they would count PETSCII codes as text. The same
    # sequences show on a modern terminal too.
    #
    # A class gets the bare names by including the module (BBS::Petscii::Screen
    # does, so its subclasses have them). A board's namespace module needs
    # ::install, because Ruby looks a bare constant up in the modules the code
    # is lexically nested in, not in what they include:
    #
    #   module UI
    #     module Petscii
    #       BBS::Petscii::Colors.install(self)
    #
    #       class Board            # nested: WH, LG, RV … work here
    #         def head = "#{WH}hello#{LG}"
    #       end
    #     end
    #   end
    module Colors
      # White (the C64's white).
      WH = Ansi::WHITE
      # Yellow.
      YE = Ansi::BRIGHT_YELLOW
      # Cyan.
      CY = Ansi::CYAN
      # Light grey, the colour of plain text.
      LG = Ansi::GREY
      # Medium grey.
      GR = Ansi::DIM_GREY
      # Dark grey.
      DG = Ansi::DARK_GREY
      # Light blue.
      LB = Ansi::BRIGHT_BLUE
      # Blue.
      BL = Ansi::BLUE
      # Light green.
      GN = Ansi::BRIGHT_GREEN
      # Light red.
      RD = Ansi::BRIGHT_RED
      # Purple.
      PU = Ansi::MAGENTA
      # Orange.
      OR = Ansi::YELLOW
      # Reverse video on.
      RV = Ansi::REVERSE
      # Reverse video off.
      RO = Ansi::REVERSE_OFF

      # Defines every colour constant of this module (WH, YE … RO) in +mod+,
      # a Module or Class, so code lexically nested in it finds the bare
      # names. A name +mod+ already defines itself is left as it is, so a
      # board can keep a colour of its own under the same name.
      #
      # Returns +mod+.
      def self.install(mod)
        constants.each do |name|
          mod.const_set(name, const_get(name)) unless mod.const_defined?(name, false)
        end
        mod
      end
    end
  end
end
