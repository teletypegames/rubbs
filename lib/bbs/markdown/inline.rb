# frozen_string_literal: true

module BBS
  module Markdown
    # The inline marks of a line of Markdown turned into SGR codes.
    module Inline
      # The spans in the order they are styled, each with its style.
      SPANS = [[LINK, :link], [CODE_SPAN, :code], [BOLD, :bold], [ITALIC_STAR, :italic], [ITALIC_UNDERSCORE, :italic]].freeze

      # Returns +text+ with links (the link text only), <tt>`code`</tt>,
      # <tt>**bold**</tt>, and <tt>*italic*</tt> or <tt>_italic_</tt> each
      # in their style of +styles+ followed by its +:base+ style, and the
      # backslash escapes removed.
      def self.style(text, styles)
        spans = SPANS.reduce(text.to_s) do |s, (pattern, role)|
          s.gsub(pattern) { "#{styles[role]}#{::Regexp.last_match(1)}#{styles[:base]}" }
        end
        spans.gsub(ESCAPED) { ::Regexp.last_match(1) }
      end
    end

    private_constant :Inline
  end
end
