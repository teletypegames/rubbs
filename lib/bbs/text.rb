# frozen_string_literal: true

module BBS
  # Text a caller typed or a remote service sent, made safe to keep and to
  # show: valid UTF-8, no control characters, no bidirectional overrides.
  #
  #   BBS::Text.clean("Ada\e[2J\u202Etxt.exe")   # => "Ada[2Jtxt.exe"
  #   BBS::Text.line("Ada\n  Lovelace\t")        # => "Ada Lovelace"
  #   BBS::Text.printable?('é')                   # => true
  module Text
    # The bidirectional embedding, override and isolate characters, which
    # can make a line read differently from what it holds.
    BIDI_CONTROLS = "\u202A-\u202E\u2066-\u2069"
    # The C0 controls except tab and LF, DEL, the C1 controls and the
    # BIDI_CONTROLS.
    CONTROLS = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F#{BIDI_CONTROLS}]/
    # A line end: CR LF, LF or CR.
    LINE_END = /\r\n|[\r\n]/
    # A run of whitespace.
    WHITESPACE = /\s+/
    # One printable character: no control, no bidirectional control.
    PRINTABLE_CHAR = /\A(?![#{BIDI_CONTROLS}])[[:print:]]\z/

    module_function

    # Returns +text+ (anything with +to_s+) as a new valid UTF-8 String with
    # invalid bytes, C0 controls (but tab and LF), DEL, C1 controls and
    # bidirectional controls removed. With <tt>keep_newlines: false</tt>
    # each line end becomes a space, so the words of two lines stay apart.
    def clean(text, keep_newlines: true)
      text = utf8(text)
      text = text.gsub(LINE_END, ' ') unless keep_newlines
      text.gsub(CONTROLS, '')
    end

    # Returns +text+ as one clean line: #clean, every run of whitespace
    # (line ends and tabs included) one space, and no space at either end.
    def line(text) = clean(text, keep_newlines: false).gsub(WHITESPACE, ' ').strip

    # Returns whether +char+ is one printable character (a String of length
    # one that PRINTABLE_CHAR matches).
    def printable?(char) = char.is_a?(String) && char.match?(PRINTABLE_CHAR)

    # Returns +text+ as a new UTF-8 String with invalid bytes removed.
    def utf8(text) = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub('')
  end
end
