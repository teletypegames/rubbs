# frozen_string_literal: true

require 'artii'

module Rubbs
  module Common
    module Text
      # Banners for plain line output: strings with CRLF line ends and ANSI
      # colours, ready to write to a session.
      module Banner
        # Returns +text+ in a double-line box, indented by two spaces, with
        # +padding+ spaces on each side of the text inside the box and a blank
        # line before and after.
        #
        # [color]   ANSI escape sequence for the box and text; default bright green
        # [padding] spaces between the text and the box sides
        def self.render(text, color: Modern::Ansi::BRIGHT_GREEN, padding: 2)
          inner = "#{' ' * padding}#{text}#{' ' * padding}"
          bar   = '═' * inner.length
          rst   = Modern::Ansi::RESET
          "#{Modern::Ansi::CRLF}  #{color}╔#{bar}╗#{rst}#{Modern::Ansi::CRLF}  " \
            "#{color}║#{inner}║#{rst}#{Modern::Ansi::CRLF}  " \
            "#{color}╚#{bar}╝#{rst}#{Modern::Ansi::CRLF * 2}"
        end

        # Returns +text+ as large FIGlet-style letters drawn by Artii, each line
        # indented by two spaces and coloured, with a blank line before and
        # after.
        #
        # [color] ANSI escape sequence for the letters; default bright green
        # [font]  the Artii font name; default <tt>'slant'</tt>
        def self.render_big(text, color: Modern::Ansi::BRIGHT_GREEN, font: 'slant')
          rst  = Modern::Ansi::RESET
          art  = Artii::Base.new(font: font).asciify(text)
          lines = art.split("\n").map { |l| "  #{color}#{l}#{rst}" }
          "#{Modern::Ansi::CRLF}#{lines.join(Modern::Ansi::CRLF)}#{Modern::Ansi::CRLF * 2}"
        end
      end
    end
  end
end
