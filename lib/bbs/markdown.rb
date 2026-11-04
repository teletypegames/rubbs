# frozen_string_literal: true

require_relative 'frame_buffer'

module BBS
  # Markdown to ANSI line array renderer.
  #
  #   BBS::Markdown.to_lines(text, width:, theme:)
  #
  # Returns an array of strings (one per terminal line) with embedded ANSI SGR
  # codes, suitable for BBS::Widgets::ScrollView. Each inline span ends with
  # the theme +:text+ SGR so that trailing text keeps the right background.
  #
  # Handled: headings, paragraphs, fenced code blocks, block quotes, bullet
  # and numbered lists, horizontal rules, GFM tables, and inline links, code,
  # bold and italic.
  module Markdown
    # A line break in the source: LF or CRLF.
    LINE_BREAK = /\r?\n/
    # A heading: one to six <tt>#</tt>, the text, optional closing marks.
    HEADING = /\A(\#{1,6})\s+(.+?)\s*#*\s*\z/
    # A horizontal rule: three or more of the same <tt>-</tt>, <tt>*</tt>
    # or <tt>_</tt>.
    RULE = /\A\s*([-*_])\1{2,}\s*\z/
    # A block quote line; the first group is the quoted text.
    QUOTE = /\A\s*>\s?(.*)/
    # A bullet list item: indent, a <tt>-</tt>, <tt>*</tt> or <tt>+</tt>
    # mark, and the text.
    BULLET_ITEM = /\A(\s*)[-*+]\s+(.+)/
    # A numbered list item: indent, the number, and the text.
    NUMBERED_ITEM = /\A(\s*)(\d+)\.\s+(.+)/
    # An indented line that may continue a list item.
    CONTINUATION = /\A\s+\S/
    # The start of a bullet or numbered list item.
    ITEM_START = /\A\s*([-*+]|\d+\.)\s+/
    # A link <tt>[text](url)</tt>; the groups are the text and the url.
    LINK = /\[([^\]]+)\]\(([^)]+)\)/
    # Inline code between backticks.
    CODE_SPAN = /`([^`]+)`/
    # Bold text between double asterisks.
    BOLD = /\*\*([^*]+)\*\*/
    # Italic text between single asterisks, not inside a word.
    ITALIC_STAR = /(?<![A-Za-z0-9*])\*([^*\s][^*]*?[^*\s]|\S)\*(?![A-Za-z0-9*])/
    # Italic text between underscores, not inside a word.
    ITALIC_UNDERSCORE = /(?<![A-Za-z0-9_])_([^_\s][^_]*?[^_\s]|\S)_(?![A-Za-z0-9_])/
    # A backslash escape of a Markdown punctuation character.
    ESCAPED = /\\([\\`*_{}\[\]()#+\-.!>])/
    # A cell of a table delimiter row: dashes with optional colons.
    DELIMITER_CELL = /\A:?-{1,}:?\z/

    # The theme role each part of the output is styled with.
    STYLE_ROLES = {
      base:   :text,
      h1:     :text_bright,
      h2:     :accent,
      h3:     :label,
      bold:   :text_bright,
      italic: :text_dim,
      code:   :label,
      link:   :accent,
      quote:  :text_dim,
      bullet: :accent,
      rule:   :label
    }.freeze

    # Renders the Markdown +text+ as terminal lines.
    #
    # [width] the line width in columns; paragraphs wrap and code lines are
    #         clipped to it
    # [theme] a BBS::Theme (or a Hash) whose +:text+, +:text_bright+,
    #         +:text_dim+, +:accent+ and +:label+ SGR styles colour the output
    #
    # Returns an Array of String, one per line.
    def self.to_lines(text, width:, theme:)
      styles = STYLE_ROLES.transform_values { |role| theme[role] }
      Renderer.new(width, styles).render(FrameBuffer.text(text).split(LINE_BREAK))
    end
  end
end

require_relative 'markdown/inline'
require_relative 'markdown/table'
require_relative 'markdown/renderer'
