# frozen_string_literal: true

module BBS
  # The last screen of a call, the way our boards hang up: thanks for
  # calling, a note, where to find more of us and its QR code (BBS::QR),
  # and NO CARRIER. On a modern
  # terminal it is one write (::modern); on a C64 a reversed bar, then the
  # modem's <tt>+++</tt>, <tt>ATH0</tt> and NO CARRIER a moment apart
  # (::petscii).
  #
  #   call do |_ctx, runner|
  #     BBS::Goodbye.modern(runner, title: 'Feedia', note: "The stories are their publishers'.")
  #     nil
  #   end
  module Goodbye
    # Where more of us are.
    URL = 'teletypegames.org'
    # The address the QR code takes a phone to: URL in capitals, which a
    # QR code holds in its alphanumeric mode, so it fits the smallest one
    # (21 modules, 13 lines); a scheme and a host name are the same in
    # either case.
    QR_URL = 'HTTPS://TELETYPEGAMES.ORG'
    # The most lines the QR code may take; an address that needs more
    # goes without one.
    QR_ROWS = 15
    # The seconds ::petscii waits before <tt>+++</tt>, before
    # <tt>ATH0</tt> and before NO CARRIER.
    PAUSES = [1.2, 0.6, 0.4].freeze

    # The text of ::modern: the screen cleared (unless +clear+ is false),
    # "Thanks for calling +title+." in white, then dim +note+ (when given)
    # and "More of us: +url+", the QR code of +qr+ (none for +nil+), then
    # NO CARRIER in red.
    def self.modern_text(title:, note: nil, url: URL, clear: true, qr: QR_URL)
      more = [note, "More of us: #{url}"].compact.join(' ')
      a = Ansi
      "#{a::RESET}#{a::CLEAR if clear}#{a::CRLF}  #{a::WHITE}Thanks for calling #{title}.#{a::RESET}#{a::CRLF}  " \
        "#{a::DIM_GREY}#{more}#{a::RESET}#{a::CRLF * 2}#{modern_code(qr)}  " \
        "#{a::BRIGHT_RED}NO CARRIER#{a::RESET}#{a::CRLF * 2}"
    end

    # Writes ::modern_text to +out+, anything with a +write+ method: a
    # BBS::FlowRunner, a BBS::Session, an IO. The arguments are those of
    # ::modern_text.
    #
    #   BBS::Goodbye.modern(runner, title: 'Commodex BBS',
    #                       note: 'Games from wikidata.org (CC0).')
    #
    # Returns +nil+.
    def self.modern(out, title:, note: nil, url: URL, clear: true, qr: QR_URL)
      out.write(modern_text(title: title, note: note, url: url, clear: clear, qr: qr))
      nil
    end

    # The goodbye of a C64 board on +screen+, a BBS::Petscii::Screen (or a
    # board's screen with +cls+, +puts+ and +say+), or on a session, which
    # gets a BBS::Petscii::Screen. It clears the screen and writes:
    #
    # - a reversed bar in +color+, +width+ columns: " +bar+", by default
    #   " thanks for calling +title+"
    # - what the block writes on the screen it is given, or else +note+
    #   (when given) and "More of us: +url+" as a dim paragraph
    # - the QR code of +qr+ in the middle (none for +nil+)
    # - after PAUSES: <tt>+++</tt>, <tt>ATH0</tt> and NO CARRIER in red
    #
    # [width] the bar's width; default the screen's +cols+ less one, or 39
    #
    #   BBS::Goodbye.petscii(screen, title: 'feedia', color: YE,
    #                        note: "The stories are their publishers'.")
    #   BBS::Goodbye.petscii(screen, title: 'the ttg wiki') do |s|
    #     s.puts " #{GR}the wiki on the web:#{LG}"
    #   end
    #
    # Returns +nil+. Raises what the session raises when the caller has
    # hung up (IOError, Errno::EPIPE …).
    def self.petscii(screen, title: nil, bar: nil, note: nil, url: URL, color: Petscii::Colors::CY, width: nil, qr: QR_URL)
      screen = Petscii::Screen.new(screen) unless screen.respond_to?(:say)
      width ||= screen.respond_to?(:cols) ? screen.cols - 1 : Petscii::COLS - 1
      screen.cls
      screen.puts
      screen.puts bar_line(bar || "thanks for calling #{title}", color, width)
      screen.puts
      block_given? ? yield(screen) : screen.say([note, "More of us: #{url}"].compact.join(' '), color: Petscii::Colors::GR)
      screen.puts
      petscii_code(screen, qr, width)
      hang_up(screen)
      nil
    end

    # The QR code of +qr+ on +screen+, centred in +width+ columns, and a
    # blank line; nothing for +nil+ or an address too long for QR_ROWS.
    def self.petscii_code(screen, qr, width)
      lines = qr_lines(qr) { |text| BBS::QR.petscii(text, rows: QR_ROWS) }
      return if lines.empty?

      indent = ' ' * [(width - FrameBuffer.visible_width(lines.first)) / 2, 0].max
      lines.each { |l| screen.puts("#{indent}#{l}") }
      screen.puts
    end

    # The QR code of +qr+ for ::modern_text: its lines indented by two
    # columns, each with a line end, and a blank line; empty for +nil+ or
    # an address too long for QR_ROWS.
    def self.modern_code(qr)
      lines = qr_lines(qr) { |text| BBS::QR.ansi(text, height: QR_ROWS) }
      lines.empty? ? '' : "#{lines.map { |l| "  #{l}#{Ansi::CRLF}" }.join}#{Ansi::CRLF}"
    end

    # The lines the block draws of +qr+; none for +nil+ or BBS::QR::TooLong.
    def self.qr_lines(qr)
      qr.nil? ? [] : yield(qr)
    rescue BBS::QR::TooLong
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
    private_class_method :hang_up, :bar_line, :petscii_code, :modern_code, :qr_lines
  end
end
