# frozen_string_literal: true

module BBS
  # A one-line input field at the cursor, for a modern terminal and a
  # Commodore 64 alike: it starts from a text that can be edited rather
  # than typed again, the cursor keys move in it, typing inserts at the
  # cursor and DEL (backspace) deletes before it. A text longer than the
  # field scrolls sideways. The text and the cursor live in a
  # BBS::TextBuffer, so the editing keys do what they do in a BBS::Editor.
  #
  # The field takes +width+ columns from where the cursor is; on a C64 keep
  # it out of the last column. It moves the cursor with a BBS::Cursor,
  # only sideways.
  #
  # Keys:
  #
  # [cursor left, right] move
  # [HOME, END]          the start and the end of the text
  # [DEL, backspace]     deletes the character before the cursor
  # [Delete]             deletes the character under the cursor
  # [RETURN]             ends the input
  # [RUN/STOP, ←, Esc]   cancels it
  #
  #   session.write ' title> '
  #   title = BBS::Field.new(session, text: post.title, width: 31, max: 80).run
  class Field
    # The keys that cancel the input.
    CANCEL_KEYS = %i[escape interrupt].freeze
    # A line end in a prompt: CRLF, CR or LF.
    LINE_END = /\r\n|\r|\n/

    # Writes +prompt+ and runs a field after it as wide as the rest of the
    # screen: +cols+ less the last line of +prompt+ and the last column.
    # Returns what #run returns: the text, or +nil+ when cancelled.
    #
    # [text] the text to start from
    # [max]  the most characters the text may hold, or +nil+
    # [mask] shown in place of every character, or +nil+
    # [cols] the screen width; default the session's
    #
    #   name = BBS::Field.ask(session, " name> ", max: 20)
    def self.ask(session, prompt, text: '', max: nil, mask: nil, cols: session.term_cols)
      session.write(prompt)
      last  = prompt.to_s.split(LINE_END, -1).last.to_s
      width = cols - 1 - FrameBuffer.visible_width(last)
      new(session, text: text, width: width, max: max, mask: mask).run
    end

    # Creates a field for +session+.
    #
    # [text]  the text to start from, the cursor at its end
    # [width] the columns the field takes, at least 2
    # [max]   the most characters the text may hold; +nil+ means TextBuffer::MAX_LENGTH
    # [mask]  shown in place of every character (for a password, e.g.
    #         <tt>'*'</tt>), or +nil+ to show the text
    def initialize(session, text: '', width:, max: nil, mask: nil)
      @session = session
      @screen  = Cursor.new(session)
      @buffer  = TextBuffer.new(text, max: max, single_line: true)
      @width   = [width, 2].max
      @mask    = mask
      @scroll  = 0
    end

    # Runs the field until RETURN or a cancel key, then writes a line end,
    # so the cursor is at the start of the next line.
    #
    # Returns the text on RETURN and +nil+ when cancelled. Raises IOError
    # when the caller hangs up.
    def run
      paint
      loop do
        key = @screen.key
        return finish(@buffer.text) if key == :enter
        return finish(nil) if CANCEL_KEYS.include?(key)

        case key
        when :home then @buffer.place(0, 0)
        when :end  then @buffer.place(0, @buffer.lines.first.length)
        else @buffer.edit(key)
        end
        paint
      end
    end

    private

    def finish(result)
      @session.write(Ansi::CRLF)
      result
    end

    # Draws the visible part of the text over the whole field and puts the
    # cursor at its place; the last column of the field is kept for the
    # cursor when it stands at the end.
    def paint
      text = @buffer.lines.first
      pos  = @buffer.pos
      @scroll = pos - @width + 1 if pos - @scroll > @width - 1
      @scroll = pos if pos < @scroll
      @scroll = [@scroll, [text.length - @width + 1, 0].max].min
      shown = text[@scroll, @width] || ''
      shown = @mask * shown.length if @mask
      out = @screen.move(1, 1) << @screen.cells(shown).ljust(@width)
      @screen.wrote(@width)
      out << @screen.move(1, 1 + pos - @scroll)
      @session.write(out)
    end
  end
end
