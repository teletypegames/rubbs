# frozen_string_literal: true

module BBS
  module Telnet
    # xterm mouse reporting of a telnet line: turning it on and off, and
    # decoding its reports into a MouseEvent (Telnet::Keys reads them).
    module Mouse
      # Turns xterm mouse reporting on: button events with drags (1002) in
      # SGR coordinates (1006).
      MOUSE_ON  = "\e[?1002h\e[?1006h"
      # Turns every xterm mouse reporting mode #enable_mouse may leave on off.
      MOUSE_OFF = "\e[?1006l\e[?1002l\e[?1000l"
      # The final byte of an X10 mouse report, <tt>ESC [ M b x y</tt>, and
      # of an SGR mouse press.
      MOUSE_PRESS = 'M'
      # The final byte of an SGR mouse release.
      MOUSE_RELEASE = 'm'
      # The parameter prefix of an SGR mouse report, <tt>ESC [ < b ; x ; y</tt>.
      SGR_MOUSE = '<'
      # The number of fields of an SGR mouse report: button, x, y.
      SGR_MOUSE_FIELDS = 3
      # Added to each byte of an X10 mouse report.
      X10_OFFSET = 32
      # The bits of a mouse report that tell the button.
      MOUSE_BUTTON_BITS = 3
      # The button value of an X10 release report (no button).
      X10_RELEASE = 3
      # Mouse report bit: the mouse moved with a button held.
      MOUSE_MOTION = 32
      # Mouse report bit: a wheel turn; button 0 is up, 1 is down.
      MOUSE_WHEEL = 64
      # The modifier bits of a mouse report and the modifiers they tell.
      MOUSE_MODIFIERS = { 4 => :shift, 8 => :meta, 16 => :ctrl }.freeze
      # The buttons by the value of MOUSE_BUTTON_BITS; any other is +:none+.
      MOUSE_BUTTONS = %i[left middle right].freeze

      # A decoded mouse report.
      #
      # [kind]   +:press+, +:release+, +:move+ (motion with a button held) or
      #          +:wheel+
      # [button] +:left+, +:middle+, +:right+ or +:none+; for +:wheel+, +:up+
      #          or +:down+
      # [x, y]   1-based terminal column and row
      # [mods]   Array of the modifiers held: +:shift+, +:meta+, +:ctrl+
      MouseEvent = Struct.new(:kind, :button, :x, :y, :mods, keyword_init: true)

      # Turns on xterm mouse reporting by writing MOUSE_ON. Does nothing when
      # it is already on or the line is in PETSCII mode.
      def enable_mouse
        return if @mouse_enabled || @petscii

        write MOUSE_ON
        @mouse_enabled = true
      end

      # Whether mouse reporting is on.
      def mouse_on? = @mouse_enabled == true

      # Turns xterm mouse reporting off, if #enable_mouse turned it on.
      def disable_mouse
        return unless @mouse_enabled

        write MOUSE_OFF
        @mouse_enabled = false
      end

      private

      # The MouseEvent of a CSI sequence with +params+ and +final+, +:escape+
      # for a broken report, +nil+ when the sequence is no mouse report.
      def mouse_report(params, final)
        return x10_mouse if final == MOUSE_PRESS && params.empty?

        sgr_mouse(params, final) if sgr_mouse?(params, final)
      end

      # The rest of an X10 report after <tt>ESC [ M</tt>: three bytes.
      def x10_mouse
        b, x, y = Array.new(3) { @client.read(1)&.ord.to_i - X10_OFFSET }
        decode_mouse(b, x, y, pressed: (b & MOUSE_BUTTON_BITS) != X10_RELEASE)
      end

      # An SGR report: +params+ is <tt><b;x;y</tt>, +final+ M or m.
      def sgr_mouse(params, final)
        fields = params[1..].split(';')
        return :escape unless fields.size == SGR_MOUSE_FIELDS

        b, x, y = fields.map(&:to_i)
        decode_mouse(b, x, y, pressed: final == MOUSE_PRESS)
      end

      def sgr_mouse?(params, final) = params.start_with?(SGR_MOUSE) && [MOUSE_PRESS, MOUSE_RELEASE].include?(final)

      def decode_mouse(b, x, y, pressed:)
        kind, button = b.anybits?(MOUSE_WHEEL) ? wheel(b) : click(b, pressed)
        MouseEvent.new(kind: kind, button: button, x: x, y: y, mods: mouse_modifiers(b))
      end

      def mouse_modifiers(b) = MOUSE_MODIFIERS.filter_map { |bit, mod| mod if b.anybits?(bit) }

      def wheel(b) = [:wheel, b.nobits?(MOUSE_BUTTON_BITS) ? :up : :down]

      def click(b, pressed)
        kind = if b.anybits?(MOUSE_MOTION) then :move
               elsif pressed then :press
               else :release
               end
        [kind, MOUSE_BUTTONS.fetch(b & MOUSE_BUTTON_BITS, :none)]
      end
    end
  end
end
