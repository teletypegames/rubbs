# frozen_string_literal: true

require 'artii'

module BBS
  module Banner
    def self.render(text, color: "\e[1;32m", padding: 2)
      inner = "#{' ' * padding}#{text}#{' ' * padding}"
      bar   = '═' * inner.length
      rst   = "\e[0m"
      "\r\n  #{color}╔#{bar}╗#{rst}\r\n" \
      "  #{color}║#{inner}║#{rst}\r\n"   \
      "  #{color}╚#{bar}╝#{rst}\r\n\r\n"
    end

    def self.render_big(text, color: "\e[1;32m", font: 'slant')
      rst  = "\e[0m"
      art  = Artii::Base.new(font: font).asciify(text)
      lines = art.split("\n").map { |l| "  #{color}#{l}#{rst}" }
      "\r\n#{lines.join("\r\n")}\r\n\r\n"
    end
  end
end
