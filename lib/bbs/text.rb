# frozen_string_literal: true

module BBS
  # Text a caller typed or a remote service sent, made safe to keep and to
  # show: valid UTF-8, no control characters, no bidirectional overrides.
  #
  #   BBS::Text.clean("Ada\e[2J‮txt.exe")   # => "Ada[2Jtxt.exe"
  #   BBS::Text.printable?('é')                   # => true
  module Text
    # The bidirectional embedding, override and isolate characters, which
    # can make a line read differently from what it holds.
    BIDI_CONTROLS = "‪-‮⁦-⁩"
    # The C0 controls except tab and LF, DEL and the C1 controls.
    CONTROLS = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F#{BIDI_CONTROLS}]/
    # The same, with LF as well.
    LINE_CONTROLS = /[\u0000-\u0008\u000A-\u001F\u007F-\u009F#{BIDI_CONTROLS}]/
    # One printable character: no control, no bidirectional control.
    PRINTABLE_CHAR = /\A(?![#{BIDI_CONTROLS}])[[:print:]]\z/

    module_function

    # Returns +text+ (anything with +to_s+) as a new valid UTF-8 String with
    # invalid bytes, C0 controls (but tab and, with +keep_newlines+, LF),
    # DEL, C1 controls and bidirectional controls removed.
    def clean(text, keep_newlines: true)
      utf8(text).gsub(keep_newlines ? CONTROLS : LINE_CONTROLS, '')
    end

    # Returns whether +char+ is one printable character (a String of length
    # one that PRINTABLE_CHAR matches).
    def printable?(char) = char.is_a?(String) && char.match?(PRINTABLE_CHAR)

    # Returns +text+ as a new UTF-8 String with invalid bytes removed.
    def utf8(text) = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub('')
  end
end
