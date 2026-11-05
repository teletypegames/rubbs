# frozen_string_literal: true

module Rubbs
  module Petscii
    # The goodbye (Rubbs::Common::Call::Goodbye) on a Commodore 64: a
    # reversed bar, the note and the address, the QR code, then the modem's
    # <tt>+++</tt>, <tt>ATH0</tt> and NO CARRIER a moment apart.
    module Goodbye
      # The seconds ::show waits before <tt>+++</tt>, before <tt>ATH0</tt>
      # and before NO CARRIER.
      PAUSES = [1.2, 0.6, 0.4].freeze

      # The goodbye on +screen+, a Screen (or a board's screen with +cls+,
      # +puts+ and +say+), or on a session, which gets a Screen. It clears the
      # screen and writes:
      #
      # - a reversed bar in +color+, +width+ columns: " +bar+", by default
      #   " thanks for calling +title+"
      # - what the block writes on the screen it is given, or else +note+
      #   (when given) and "More of us: +url+" as a dim paragraph
      # - the QR code of +qr+ in the middle (none for +nil+)
      # - after PAUSES: <tt>+++</tt>, <tt>ATH0</tt> and NO CARRIER in red
      #
      # [width] the bar's width; default the screen's +cols+ less one, or 39
      # [art]   lines written under the bar (a logo), or +nil+
      #
      #   Rubbs::Petscii::Goodbye.show(screen, title: 'feedia', color: YE, note: "The stories are their publishers'.")
      #   Rubbs::Petscii::Goodbye.show(screen, title: 'the ttg wiki') do |s|
      #     s.puts " #{GR}the wiki on the web:#{LG}"
      #   end
      #
      # Returns +nil+. Raises what the session raises when the caller has
      # hung up (IOError, Errno::EPIPE …).
      def self.show(
        screen,
        title: Rubbs.config.title,
        bar: nil,
        note: nil,
        url: Rubbs.config.preset.url,
        color: Colors::CY,
        width: nil,
        qr: Rubbs.config.preset.qr,
        art: nil,
        greeting: Common::Call::Goodbye::GREETING
      )
        screen = Screen.new(screen) unless screen.respond_to?(:say)
        width ||= bar_width(screen)
        screen.cls
        screen.puts
        [bar_line(bar || "#{greeting} #{title}".downcase, color, width), '', *Array(art)].each { |line| screen.puts(line) }
        block_given? ? yield(screen) : screen.say(Common::Call::Goodbye.more_text(note, url), color: Colors::GR)
        screen.puts
        code(screen, qr, width)
        hang_up(screen)
        nil
      end

      def self.bar_width(screen) = (screen.respond_to?(:cols) ? screen.cols : COLS) - 1

      # The QR code of +qr+ on +screen+, centred in +width+ columns, and a
      # blank line; nothing for +nil+ or an address too long.
      def self.code(screen, qr, width)
        rows  = Common::Call::Goodbye::QR_ROWS
        lines = Common::Call::Goodbye.qr_lines(qr) { |text| Common::Text::QR.petscii(text, rows: rows) }
        return if lines.empty?

        indent = ' ' * [(width - Modern::FrameBuffer.visible_width(lines.first)) / 2, 0].max
        lines.each { |l| screen.puts("#{indent}#{l}") }
        screen.puts
      end

      # +text+ on a reversed bar in +color+, +width+ columns.
      def self.bar_line(text, color, width)
        c = Colors
        " #{color}#{c::RV}#{" #{text}".ljust(width)[0, width]}#{c::RO}#{c::LG}"
      end

      # +++, ATH0 and NO CARRIER on +screen+, PAUSES apart.
      def self.hang_up(screen)
        c = Colors
        sleep PAUSES[0]
        screen.puts " #{c::LG}+++"
        sleep PAUSES[1]
        screen.puts ' ATH0'
        sleep PAUSES[2]
        screen.puts " #{c::RD}NO CARRIER#{c::LG}"
        screen.puts
      end

      private_class_method :bar_width, :code, :bar_line, :hang_up
    end
  end
end
