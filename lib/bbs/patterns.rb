# frozen_string_literal: true

module BBS
  # Text patterns used by more than one class.
  module Patterns
    # A run of whitespace.
    WHITESPACE = /\s+/
    # A Markdown link <tt>[label](url)</tt>; the first group is the label.
    MARKDOWN_LINK = /\[([^\]]+)\]\([^)]+\)/
    # A Markdown mark character dropped from plain text.
    MARKDOWN_MARK = /[#*_`~>|\\]/
    # A run of line ends, LF or CRLF.
    LINE_BREAKS = /\r?\n+/
  end
end
