# frozen_string_literal: true

module BBS
  class FrameBuffer
    # The class methods of FrameBuffer for ANSI text, rubbs' one set of
    # tools for it: FrameBuffer.plain strips the colours, .visible_width
    # measures, .clip_ansi cuts and .wrap_ansi word-wraps (the one
    # word-wrap), all keeping the escape sequences where they belong.
    module AnsiText
      # Returns +value+ as a UTF-8 String a regexp can read: a binary String
      # is taken as UTF-8, another encoding is converted, and invalid bytes
      # become <tt>?</tt>.
      def text(value)
        s = value.to_s
        s = utf8(s) unless s.encoding == Encoding::UTF_8
        s.valid_encoding? ? s : s.scrub('?')
      end

      # Returns +s+ in UTF-8: bytes of a binary String as they are, another
      # encoding converted (what does not convert becomes <tt>?</tt>).
      def utf8(s)
        return s.dup.force_encoding(Encoding::UTF_8) if s.encoding == Encoding::BINARY

        s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
      end

      # Returns +text+ (anything with +to_s+) as UTF-8 without its ANSI
      # escape sequences: the one way rubbs strips colours from text.
      def plain(text) = text(text).gsub(Ansi::CSI_RE, '')

      # Returns the number of characters of +text+ left once its ANSI escape
      # sequences are removed.
      def visible_width(text) = plain(text).length

      # Returns +text+ cut so that at most +max_width+ characters are visible.
      # Escape sequences up to the cut are kept (they take no width); an
      # escape sequence the text cuts off ends it. An empty String when
      # +max_width+ is zero or less.
      def clip_ansi(text, max_width)
        out     = +''
        visible = 0
        text(text).scan(ANSI_TOKEN) do |seq, cut, char|
          break if cut || (char && visible >= max_width)

          out << (seq || char)
          visible += 1 if char
        end
        out
      end

      # Word-wraps the ANSI-styled +text+ to lines of at most +width+ visible
      # characters and returns them as an Array of Strings, with trailing
      # spaces removed. A word longer than +width+ stays on a line of its own.
      #
      # The style is carried across wrapped lines: when an SGR sequence is
      # active at a wrap point, the next line starts with that sequence again.
      # Returns <tt>['']</tt> when +width+ is zero or less.
      def wrap_ansi(text, width)
        return [''] if width <= 0

        s = text(text)
        visible_width(s) <= width ? [s] : Wrap.new(width).lines(s)
      end
    end

    extend AnsiText
  end
end
