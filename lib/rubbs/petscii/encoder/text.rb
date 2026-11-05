# frozen_string_literal: true

module Rubbs
  module Petscii
    class Encoder
      # The characters an Encoder writes: each as its PETSCII glyph, the
      # column counted so a full row wraps once.
      module Text
        private

        # Control codes keep the column; every other character takes one.
        def text(ch, out)
          glyph(ch).each_char do |g|
            out << g.ord.chr
            quote_off(out) if g == '"'
            advance unless CONTROLS.include?(g.ord)
          end
        end

        def advance
          @col += 1
          @wrapped = false
          return unless @col >= COLS

          @col     = 0
          @wrapped = true
        end

        # A " puts the C64 screen editor in quote mode, where colour and cursor
        # codes show as reversed symbols instead of working until the next "
        # or RETURN. A second " ends it; the cursor goes back onto it and a
        # space covers it. Too near the right edge the second " would wrap the
        # line, so there the quote mode stays until the RETURN.
        def quote_off(out)
          return if @col > COLS - QUOTE_ROOM

          out << bytes("\"#{LEFT} #{LEFT}")
        end

        def glyph(ch)
          o = ch.ord
          return (o + SHIFT_OFFSET).chr(Encoding::UTF_8) if ASCII_UPPER.cover?(o)
          return (o - CASE_OFFSET).chr if ASCII_LOWER.cover?(o)
          return ch if SAME_AS_ASCII.cover?(o) || [LEFT_BRACKET, RIGHT_BRACKET].include?(o)

          half_block(ch) || Glyphs::GLYPHS[ch] || accentless(ch)
        end

        # The blocks the lowercase set draws in reverse video.
        def half_block(ch)
          case ch
          when '█' then @rvs ? "#{RVS_OFF} #{RVS_ON}" : "#{RVS_ON} #{RVS_OFF}"
          when '▀' then "#{RVS_ON}#{Glyphs::GLYPHS['▄']}#{RVS_OFF}"
          when '▐' then "#{RVS_ON}#{Glyphs::GLYPHS['▌']}#{RVS_OFF}"
          end
        end

        def accentless(ch)
          base = Petscii.base(ch)
          base.ascii_only? && !base.empty? && base != ch ? base.each_char.map { |c| glyph(c) }.join : '?'
        end
      end

      include Text
    end
  end
end
