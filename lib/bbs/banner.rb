# frozen_string_literal: true

require 'artii'

module BBS
  # Banners for plain line output: strings with CRLF line ends and ANSI
  # colours, ready to write to a session.
  module Banner
    # Returns +text+ in a double-line box, indented by two spaces, with
    # +padding+ spaces on each side of the text inside the box and a blank
    # line before and after.
    #
    # [color]   ANSI escape sequence for the box and text; default bright green
    # [padding] spaces between the text and the box sides
    def self.render(text, color: "\e[1;32m", padding: 2)
      inner = "#{' ' * padding}#{text}#{' ' * padding}"
      bar   = '═' * inner.length
      rst   = "\e[0m"
      "\r\n  #{color}╔#{bar}╗#{rst}\r\n" \
      "  #{color}║#{inner}║#{rst}\r\n"   \
      "  #{color}╚#{bar}╝#{rst}\r\n\r\n"
    end

    # Returns +text+ as large FIGlet-style letters drawn by Artii, each line
    # indented by two spaces and coloured, with a blank line before and
    # after.
    #
    # [color] ANSI escape sequence for the letters; default bright green
    # [font]  the Artii font name; default <tt>'slant'</tt>
    def self.render_big(text, color: "\e[1;32m", font: 'slant')
      rst  = "\e[0m"
      art  = Artii::Base.new(font: font).asciify(text)
      lines = art.split("\n").map { |l| "  #{color}#{l}#{rst}" }
      "\r\n#{lines.join("\r\n")}\r\n\r\n"
    end
  end
end
