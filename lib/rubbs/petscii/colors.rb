# frozen_string_literal: true

module Rubbs
  module Petscii
    # The colours of a line-by-line C64 board as two-letter constants: the
    # C64 names of the Rubbs::Modern::Ansi palette, so each is an ANSI SGR sequence. A
    # PETSCII session (<tt>session.petscii!</tt>) turns them into the C64's
    # own colour codes, and the width helpers of rubbs (Rubbs::Modern::FrameBuffer)
    # know ANSI, where they would count PETSCII codes as text. The same
    # sequences show on a modern terminal too.
    #
    # A class gets the bare names by including the module (Rubbs::Petscii::Screen
    # does, so its subclasses have them). A board's namespace module needs
    # ::install, because Ruby looks a bare constant up in the modules the code
    # is lexically nested in, not in what they include:
    #
    #   module UI
    #     module Petscii
    #       Rubbs::Petscii::Colors.install(self)
    #
    #       class Board            # nested: WH, LG, RV … work here
    #         def head = "#{WH}hello#{LG}"
    #       end
    #     end
    #   end
    module Colors
      # White (the C64's white).
      WH = Modern::Ansi::WHITE
      # Yellow.
      YE = Modern::Ansi::BRIGHT_YELLOW
      # Cyan.
      CY = Modern::Ansi::CYAN
      # Light grey, the colour of plain text.
      LG = Modern::Ansi::GREY
      # Medium grey.
      GR = Modern::Ansi::DIM_GREY
      # Dark grey.
      DG = Modern::Ansi::DARK_GREY
      # Light blue.
      LB = Modern::Ansi::BRIGHT_BLUE
      # Blue.
      BL = Modern::Ansi::BLUE
      # Light green.
      GN = Modern::Ansi::BRIGHT_GREEN
      # Light red.
      RD = Modern::Ansi::BRIGHT_RED
      # Dark red.
      DR = Modern::Ansi::RED
      # Purple.
      PU = Modern::Ansi::MAGENTA
      # Orange.
      OR = Modern::Ansi::YELLOW
      # Reverse video on.
      RV = Modern::Ansi::REVERSE
      # Reverse video off.
      RO = Modern::Ansi::REVERSE_OFF

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
