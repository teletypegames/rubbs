# frozen_string_literal: true

module BBS
  # The text and the cursor of an input, without a screen: BBS::Field and
  # BBS::Editor keep theirs in one and draw it each in their own way, so a
  # key does the same in both.
  #
  # The text is a list of lines; the cursor is a line index and a character
  # position in that line.
  #
  #   buffer = BBS::TextBuffer.new('Hello', max: 80)
  #   buffer.edit('!')        # => true
  #   buffer.text             # => "Hello!"
  class TextBuffer
    # The control characters of a new text that become a space: tab and CR.
    SPACED_CONTROLS = "\t\r"
    # One printable character, the only kind #edit inserts
    # (BBS::Text::PRINTABLE_CHAR).
    PRINTABLE_CHAR = Text::PRINTABLE_CHAR
    # The most characters a buffer holds when it is given no +max+: 64 KiB.
    MAX_LENGTH = 65_536

    # The lines of the text, without line ends (Array of String).
    attr_reader :lines
    # The cursor's line, an index into #lines.
    attr_reader :line
    # The cursor's position in its line, 0 to the line's length.
    attr_reader :pos

    # Creates a buffer holding +text+ with the cursor at its end.
    #
    # [text]        the text to start from; lines end with LF, tabs become
    #               spaces
    # [max]         the most characters the text may hold (line ends count
    #               as one); +nil+ means MAX_LENGTH
    # [single_line] one line: line ends in +text+ become spaces and RETURN
    #               does not split the line
    def initialize(text = '', max: nil, single_line: false)
      @max    = max || MAX_LENGTH
      @single = single_line
      text    = text.to_s.gsub(Ansi::CRLF, "\n").tr(SPACED_CONTROLS, '  ')
      text    = text.tr("\n", ' ') if @single
      @lines  = text.split("\n", -1).map(&:dup)
      @lines  = [+''] if @lines.empty?
      @line   = @lines.size - 1
      @pos    = @lines.last.length
    end

    # The text, the lines joined by LF.
    def text = @lines.join("\n")

    # The number of characters in the text, line ends counted as one each.
    def length = @lines.sum(&:length) + @lines.size - 1

    # Puts the cursor on +line+ at +pos+, both clamped to the text.
    def place(line, pos)
      @line = line.clamp(0, @lines.size - 1)
      @pos  = pos.clamp(0, @lines[@line].length)
    end

    # Applies the editing key +key+ (as BBS::Telnet#readkey returns it):
    #
    # [a one-character String] inserted at the cursor, unless the text is
    #                          at +max+ or it is not printable
    # [+:backspace+]           deletes before the cursor, joining the line
    #                          to the one above at its start
    # [+:delete+]              deletes under the cursor, joining the next
    #                          line at the end of this one
    # [+:left+, +:right+]      move one character, across line ends
    # [+:enter+]               splits the line at the cursor (not in a
    #                          single-line buffer)
    #
    # Returns true when the key was one of these, false for any other key,
    # which the caller handles.
    def edit(key)
      case key
      when String     then insert(key)
      when :backspace then backspace
      when :delete    then delete
      when :left      then left
      when :right     then right
      when :enter
        return false if @single

        split_line
      else return false
      end
      true
    end

    private

    def full? = length >= @max

    def insert(char)
      return if full? || !char.match?(PRINTABLE_CHAR)

      @lines[@line].insert(@pos, char)
      @pos += 1
    end

    def split_line
      return if full?

      rest = @lines[@line].slice!(@pos..)
      @lines.insert(@line + 1, rest)
      @line += 1
      @pos   = 0
    end

    def backspace
      if @pos.positive?
        @lines[@line].slice!(@pos - 1)
        @pos -= 1
      elsif @line.positive?
        @pos = @lines[@line - 1].length
        @lines[@line - 1] << @lines.delete_at(@line)
        @line -= 1
      end
    end

    def delete
      if @pos < @lines[@line].length
        @lines[@line].slice!(@pos)
      elsif @line < @lines.size - 1
        @lines[@line] << @lines.delete_at(@line + 1)
      end
    end

    def left
      if @pos.positive?
        @pos -= 1
      elsif @line.positive?
        @line -= 1
        @pos = @lines[@line].length
      end
    end

    def right
      if @pos < @lines[@line].length
        @pos += 1
      elsif @line < @lines.size - 1
        @line += 1
        @pos = 0
      end
    end
  end
end
