# frozen_string_literal: true

module BBS
  module Petscii
    # The colours of a line-by-line C64 board as two-letter constants, each
    # an ANSI SGR sequence: a PETSCII session (<tt>session.petscii!</tt>)
    # turns them into the C64's own colour codes, and the width helpers of
    # rubbs (BBS::FrameBuffer) know ANSI, where they would count PETSCII
    # codes as text. The same sequences show on a modern terminal too.
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
      WH = "\e[1;37m"
      # Yellow.
      YE = "\e[1;33m"
      # Cyan.
      CY = "\e[0;36m"
      # Light grey, the colour of plain text.
      LG = "\e[0;37m"
      # Medium grey.
      GR = "\e[2;37m"
      # Dark grey.
      DG = "\e[1;30m"
      # Light blue.
      LB = "\e[1;34m"
      # Blue.
      BL = "\e[0;34m"
      # Light green.
      GN = "\e[1;32m"
      # Light red.
      RD = "\e[1;31m"
      # Purple.
      PU = "\e[0;35m"
      # Orange.
      OR = "\e[0;33m"
      # Reverse video on.
      RV = "\e[7m"
      # Reverse video off.
      RO = "\e[27m"

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
