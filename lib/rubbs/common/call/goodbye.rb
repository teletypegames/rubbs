# frozen_string_literal: true

module Rubbs
  module Common
    module Call
      # The last screen of a call: thanks for calling, a note, where to find
      # more of the board's family and its QR code (Rubbs::Common::Text::QR), and NO CARRIER.
      # The board's name, the address and the QR code come from Rubbs.config
      # (+title+ and the Rubbs::Common::Board::Preset); a board that uses Rubbs.board only says
      # <tt>goodbye 'a note'</tt>. On a modern
      # terminal it is one write (::modern); on a C64 a reversed bar, then the
      # modem's <tt>+++</tt>, <tt>ATH0</tt> and NO CARRIER a moment apart
      # (::petscii).
      #
      #   Rubbs::Common::Call::Goodbye.show(session, note: "The stories are their publishers'.")
      module Goodbye
        # What the goodbye says before the board's name.
        GREETING = 'Thanks for calling'
        # The most lines the QR code may take; an address that needs more
        # goes without one.
        QR_ROWS = 15
        # The seconds ::petscii waits before <tt>+++</tt>, before
        # <tt>ATH0</tt> and before NO CARRIER.
        PAUSES = [1.2, 0.6, 0.4].freeze

        # The text of ::modern: the screen cleared (unless +clear+ is false),
        # "+greeting+ +title+." in white (default "Thanks for calling"), then dim +note+ (when given)
        # and "More of us: +url+", the QR code of +qr+ (none for +nil+), then
        # NO CARRIER in red.
        def self.modern_text(
          title: Rubbs.config.title,
          note: nil,
          url: Rubbs.config.preset.url,
          clear: true,
          qr: Rubbs.config.preset.qr,
          greeting: GREETING
        )
          more = more_text(note, url)
          a = Modern::Ansi
          "#{a::RESET}#{a::CLEAR if clear}#{a::CRLF}  #{a::WHITE}#{greeting} #{title}.#{a::RESET}#{a::CRLF}  " \
            "#{a::DIM_GREY}#{more}#{a::RESET}#{a::CRLF * 2}#{modern_code(qr)}  " \
            "#{a::BRIGHT_RED}NO CARRIER#{a::RESET}#{a::CRLF * 2}"
        end

        # Writes ::modern_text to +out+, anything with a +write+ method: a
        # Rubbs::Common::Call::FlowRunner, a Rubbs::Common::Line::Session, an IO. The arguments are those of
        # ::modern_text.
        #
        #   Rubbs::Common::Call::Goodbye.modern(runner, title: 'Commodex BBS',
        #                       note: 'Games from wikidata.org (CC0).')
        #
        # Returns +nil+.
        def self.modern(
          out,
          title: Rubbs.config.title,
          note: nil,
          url: Rubbs.config.preset.url,
          clear: true,
          qr: Rubbs.config.preset.qr,
          greeting: GREETING
        )
          out.write(modern_text(title: title, note: note, url: url, clear: clear, qr: qr, greeting: greeting))
          nil
        end

        # The goodbye of a C64 board on +screen+, a Rubbs::Petscii::Screen (or a
        # board's screen with +cls+, +puts+ and +say+), or on a session, which
        # gets a Rubbs::Petscii::Screen. It clears the screen and writes:
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
        #   Rubbs::Common::Call::Goodbye.petscii(screen, title: 'feedia', color: YE,
        #                        note: "The stories are their publishers'.")
        #   Rubbs::Common::Call::Goodbye.petscii(screen, title: 'the ttg wiki') do |s|
        #     s.puts " #{GR}the wiki on the web:#{LG}"
        #   end
        #
        # Returns +nil+. Raises what the session raises when the caller has
        # hung up (IOError, Errno::EPIPE …).
        def self.petscii(
          screen,
          title: Rubbs.config.title,
          bar: nil,
          note: nil,
          url: Rubbs.config.preset.url,
          color: Petscii::Colors::CY,
          width: nil,
          qr: Rubbs.config.preset.qr,
          art: nil,
          greeting: GREETING
        )
          screen = Petscii::Screen.new(screen) unless screen.respond_to?(:say)
          width ||= bar_width(screen)
          screen.cls
          screen.puts
          [bar_line(bar || "#{greeting} #{title}".downcase, color, width), '', *Array(art)]
            .each { |line| screen.puts(line) }
          block_given? ? yield(screen) : screen.say(more_text(note, url), color: Petscii::Colors::GR)
          screen.puts
          petscii_code(screen, qr, width)
          hang_up(screen)
          nil
        end

        # The goodbye of the face of +session+: ::petscii on a PETSCII line,
        # ::modern otherwise, with the board's title and preset. +note+ is the
        # board's own line (its sources, its licence); +clear+ (modern: whether
        # the screen is cleared first), +color+, +bar+ and +art+ (C64: the
        # bar's colour and text, lines under it) are those of ::modern and
        # ::petscii, +greeting+ what both say before the board's name. A dropped line is not an error here: the caller has gone
        # already.
        #
        # Returns +nil+.
        def self.show(session, note: nil, clear: true, color: Petscii::Colors::CY, bar: nil, art: nil, greeting: GREETING)
          if session.respond_to?(:petscii?) && session.petscii?
            petscii(session, note: note, color: color, bar: bar, art: art, greeting: greeting)
          else
            modern(session, note: note, clear: clear, greeting: greeting)
          end
        rescue *Line::LINE_DROPPED
          nil
        end

        def self.bar_width(screen) = (screen.respond_to?(:cols) ? screen.cols : Petscii::COLS) - 1

        def self.more_text(note, url) = [note, ("More of us: #{url}" if url)].compact.join(' ')

        # The QR code of +qr+ on +screen+, centred in +width+ columns, and a
        # blank line; nothing for +nil+ or an address too long for QR_ROWS.
        def self.petscii_code(screen, qr, width)
          lines = qr_lines(qr) { |text| Text::QR.petscii(text, rows: QR_ROWS) }
          return if lines.empty?

          indent = ' ' * [(width - Modern::FrameBuffer.visible_width(lines.first)) / 2, 0].max
          lines.each { |l| screen.puts("#{indent}#{l}") }
          screen.puts
        end

        # The QR code of +qr+ for ::modern_text: its lines indented by two
        # columns, each with a line end, and a blank line; empty for +nil+ or
        # an address too long for QR_ROWS.
        def self.modern_code(qr)
          lines = qr_lines(qr) { |text| Text::QR.ansi(text, height: QR_ROWS) }
          lines.empty? ? '' : "#{lines.map { |l| "  #{l}#{Modern::Ansi::CRLF}" }.join}#{Modern::Ansi::CRLF}"
        end

        # The lines the block draws of +qr+; none for +nil+ or Rubbs::Common::Text::QR::TooLong.
        def self.qr_lines(qr)
          qr.nil? ? [] : yield(qr)
        rescue Text::QR::TooLong
          []
        end

        # +text+ on a reversed bar in +color+, +width+ columns.
        def self.bar_line(text, color, width)
          c = Petscii::Colors
          " #{color}#{c::RV}#{" #{text}".ljust(width)[0, width]}#{c::RO}#{c::LG}"
        end

        # +++, ATH0 and NO CARRIER on +screen+, PAUSES apart.
        def self.hang_up(screen)
          c = Petscii::Colors
          sleep PAUSES[0]
          screen.puts " #{c::LG}+++"
          sleep PAUSES[1]
          screen.puts ' ATH0'
          sleep PAUSES[2]
          screen.puts " #{c::RD}NO CARRIER#{c::LG}"
          screen.puts
        end
        private_class_method :bar_width, :more_text, :hang_up, :bar_line, :petscii_code, :modern_code, :qr_lines
      end
    end
  end
end
