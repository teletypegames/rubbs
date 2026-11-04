# frozen_string_literal: true

# Markdown samples the renderer is checked against (see markdown_test.rb).
MARKDOWN_CORPUS = {
  'headings'       => "# Title one\n## Second **bold**\n### Third\n#### Fourth ##",
  'paragraph'      => "A long paragraph that keeps going and going so that it has to wrap\n" \
                      "across   several lines of the narrow column, with **bold**, *italic*, _under_,\n" \
                      "`code` and a [link](http://x.y) in it.\n" \
                      "\n" \
                      'Second paragraph.',
  'escapes'        => 'Not \*italic\* and snake_case_word and 2*3*4 and \# hash',
  'fence'          => "Before\n" \
                      "```ruby\n" \
                      "def hello = 'a very long line of code that is longer than the width of the column'\n  " \
                      "# **not bold**\n" \
                      "```\n" \
                      'After',
  'quote'          => "> A quoted line that is long enough to wrap inside the quote bar here.\n>\n> **bold** quote",
  'bullets'        => "- one\n" \
                      "- two that is a long item which wraps onto a second and a third line maybe\n  " \
                      "continued here\n" \
                      "* star\n  " \
                      "+ nested plus\n" \
                      '- last',
  'numbers'        => "1. first\n" \
                      "2. second with a long body that wraps across the column width for sure\n   " \
                      "and a continuation\n" \
                      '10. tenth',
  'rules'          => "above\n---\n***\n___\nbelow",
  'table'          => "| Name | Count | Mid |\n|:-----|------:|:---:|\n| apple | 1 | x |\n| banana **b** | 22 | yy |\n| c |",
  'wide_table'     => "a|b|c\n" \
                      "---|---|---\n" \
                      'something quite long in a cell | another long cell value here | third cell that is also long',
  'not_a_table'    => "a | b\nno separator here\n| x |",
  'mixed'          => "# Head\npara line\n- item\nmore para\n> quote\n\n\n```\ncode\n```\n|h|\n|-|\n|v|\ntrailing",
  'empty'          => '',
  'crlf'           => "line one\r\nline two\r\n\r\n# head\r\n",
  'unclosed_fence' => "```\ncode forever\n- not a list"
}.freeze
