# frozen_string_literal: true

module Rubbs
  module Modern
    # The goodbye (Rubbs::Common::Call::Goodbye) on a modern terminal, in one
    # write: "+greeting+ +title+.", the note and the address, the QR code, NO
    # CARRIER.
    #
    #   Rubbs::Modern::Goodbye.show(runner, title: 'Commodex BBS', note: 'Games from wikidata.org (CC0).')
    module Goodbye
      # The text of the goodbye: the screen cleared (unless +clear+ is
      # false), "+greeting+ +title+." in white, then dim +note+ (when given)
      # and "More of us: +url+", the QR code of +qr+ (none for +nil+), then NO
      # CARRIER in red.
      def self.text(
        title: Rubbs.config.title,
        note: nil,
        url: Rubbs.config.preset.url,
        clear: true,
        qr: Rubbs.config.preset.qr,
        greeting: Common::Call::Goodbye::GREETING
      )
        more = Common::Call::Goodbye.more_text(note, url)
        a = Ansi
        "#{a::RESET}#{a::CLEAR if clear}#{a::CRLF}  #{a::WHITE}#{greeting} #{title}.#{a::RESET}#{a::CRLF}  " \
          "#{a::DIM_GREY}#{more}#{a::RESET}#{a::CRLF * 2}#{code(qr)}  " \
          "#{a::BRIGHT_RED}NO CARRIER#{a::RESET}#{a::CRLF * 2}"
      end

      # Writes ::text to +out+, anything with a +write+ method: a
      # Rubbs::Common::Call::FlowRunner, a Rubbs::Common::Line::Session, an IO.
      # The arguments are those of ::text. Returns +nil+.
      def self.show(
        out,
        title: Rubbs.config.title,
        note: nil,
        url: Rubbs.config.preset.url,
        clear: true,
        qr: Rubbs.config.preset.qr,
        greeting: Common::Call::Goodbye::GREETING
      )
        out.write(text(title: title, note: note, url: url, clear: clear, qr: qr, greeting: greeting))
        nil
      end

      # The QR code of +qr+: its lines indented by two columns, each with a
      # line end, and a blank line; empty for +nil+ or an address too long.
      def self.code(qr)
        lines = Common::Call::Goodbye.qr_lines(qr) { |t| Common::Text::QR.ansi(t, height: Common::Call::Goodbye::QR_ROWS) }
        lines.empty? ? '' : "#{lines.map { |l| "  #{l}#{Ansi::CRLF}" }.join}#{Ansi::CRLF}"
      end

      private_class_method :code
    end
  end
end
