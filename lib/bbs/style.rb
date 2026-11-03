# frozen_string_literal: true

module BBS
  # SGR styles for a modern terminal by what they are, not by their escape
  # sequence: a board names its colours once (<tt>GREEN = BBS::Style[fg: 84]</tt>)
  # and writes the names. A style is a frozen String, so it goes into text
  # as it is and into a BBS::FrameBuffer as an +sgr:+.
  #
  #   ACCENT = BBS::Style[fg: 84]                  # "\e[38;5;84m"
  #   LIT    = BBS::Style[fg: 84, bg: 235, bold: true]
  #   session.write("#{ACCENT}Online#{BBS::Style::RESET}")
  module Style
    # The SGR reset: the terminal's own colours and no attribute.
    RESET = Ansi::RESET
    # The SGR parameters of the attributes Style.[] takes.
    ATTRIBUTES = { bold: 1, faint: 2, italic: 3, underline: 4, blink: 5, reverse: 7 }.freeze
    # The colours of the 16-colour palette by name, as their offset from
    # 30 (foreground) or 40 (background); the +bright_+ ones from 90 or
    # 100.
    NAMES = {
      black: 0, red: 1, green: 2, yellow: 3, blue: 4, magenta: 5, cyan: 6, white: 7, default: 9
    }.freeze

    # The SGR sequence of a style:
    #
    # [fg]   the text colour: an xterm-256 index (0-255), a name of NAMES
    #        (+:green+, <tt>:bright_green</tt>), or <tt>[r, g, b]</tt> for
    #        true colour
    # [bg]   the background, the same way
    # [attributes] +true+ for each of ATTRIBUTES wanted: <tt>bold: true</tt>
    #
    # Returns a frozen String, empty for no style at all. Raises
    # ArgumentError for a colour or an attribute it does not know.
    #
    #   BBS::Style[fg: 221]                     # => "\e[38;5;221m"
    #   BBS::Style[fg: :bright_red, bold: true] # => "\e[1;91m"
    def self.[](fg: nil, bg: nil, **attributes)
      params = attributes.select { |_, on| on }.keys.map do |name|
        ATTRIBUTES.fetch(name) { raise ArgumentError, "not an attribute: #{name.inspect}" }
      end
      params << color(fg, 30) if fg
      params << color(bg, 40) if bg
      params.empty? ? '' : "#{Ansi::CSI}#{params.join(';')}m".freeze
    end

    # +text+ in +style+ (a String of Style.[]), the style reset after it.
    #
    #   BBS::Style.paint(ACCENT, 'Online')
    def self.paint(style, text) = "#{style}#{text}#{RESET}"

    # The SGR parameters of +value+ as a colour from +base+ (30 for the
    # text, 40 for the background).
    def self.color(value, base)
      case value
      when Integer then color_index(value, base)
      when Array then "#{base + 8};2;#{value.map { |v| Integer(v).clamp(0, 255) }.join(';')}"
      else named(value, base)
      end
    end

    # An xterm-256 colour +index+ from +base+.
    def self.color_index(index, base)
      raise ArgumentError, "not a 256-colour index: #{index}" unless index.between?(0, 255)

      "#{base + 8};5;#{index}"
    end

    # A colour of NAMES, +bright_+ before it for the bright one, from +base+.
    def self.named(name, base)
      key = name.to_s.downcase
      bright = key.delete_prefix!('bright_')
      offset = NAMES.fetch(key.to_sym) { raise ArgumentError, "not a colour: #{name.inspect}" }
      (bright ? base + 60 + offset : base + offset).to_s
    end

    private_class_method :color, :color_index, :named
  end
end
