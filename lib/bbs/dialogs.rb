# frozen_string_literal: true

require_relative 'window'
require_relative 'widgets'

module BBS
  # Ready-made modal dialogs for a BBS::Application: a message, a yes/no
  # confirmation, and a one-line input. Each opens a centred Window on +app+
  # and returns it; the buttons close it.
  #
  #   BBS::Dialogs.confirm(app, 'Delete this post?', on_yes: -> { delete(post) })
  module Dialogs
    # Cells kept free between a dialog and each screen edge.
    SCREEN_MARGIN = 2
    # Columns between the window's left edge and its text, and between the
    # text and the right edge.
    PADDING = 2
    # The window row of the first text line, below the top border.
    TEXT_TOP = 1
    # Columns of a message or confirm box beside its wrapped text.
    TEXT_CHROME = 6
    # Rows of a message or confirm box beside its text lines: the borders,
    # the blank lines and the button row.
    CHROME_ROWS = 5
    # The button row, counted up from the bottom edge.
    BUTTON_ROW = 2
    # Width of an OK, Yes or No button.
    BUTTON_WIDTH = 8
    # Width of the Cancel button.
    CANCEL_WIDTH = 10
    # Columns between the middle of the window and each of two buttons side
    # by side.
    HALF_GAP = 1
    # The width a message without a fixed width and a confirm text are
    # wrapped at.
    WRAP_WIDTH = 50
    # The narrowest message box.
    MESSAGE_MIN_WIDTH = 30
    # The narrowest confirm box.
    CONFIRM_MIN_WIDTH = 36
    # The default width of an input box.
    INPUT_WIDTH = 50
    # The height of an input box.
    INPUT_HEIGHT = 7
    # The window row of the text field of an input box.
    INPUT_ROW = 3

    # Builds a modal Window of +width+ x +height+ cells centred on +app+'s
    # screen, shrunk to leave a two-cell margin. The window is not opened.
    #
    # Returns the Window.
    def self.centred_window(app, width:, height:, title: nil)
      cols  = app.cols
      rows  = app.rows
      w     = [width, cols - (2 * SCREEN_MARGIN)].min
      h     = [height, rows - (2 * SCREEN_MARGIN)].min
      x     = ((cols - w) / 2) + 1
      y     = ((rows - h) / 2) + 1
      win   = Window.new(title: title, modal: true)
      win.layout(x, y, w, h)
      win
    end

    # Opens a message box with +text+, word-wrapped, and an OK button that
    # closes it. +width+ fixes the box width; by default it fits the text.
    #
    # Returns the Window.
    def self.message(app, text, title: ' Message ', width: nil)
      lines  = wrap(text, width ? width - TEXT_CHROME : WRAP_WIDTH)
      window = text_box(app, lines, width || fit(lines, MESSAGE_MIN_WIDTH), title)
      ok     = Widgets::Button.new(label: '&OK', on_click: closer(app, window))
      place(window, ok, (window.bounds.width - BUTTON_WIDTH) / 2, button_row(window), BUTTON_WIDTH)
      show(app, window)
    end

    # Opens a Yes/No box with +text+. Each button closes the box, then calls
    # +on_yes+ or +on_no+ when given.
    #
    # Returns the Window.
    def self.confirm(app, text, title: ' Confirm ', on_yes: nil, on_no: nil)
      lines  = wrap(text, WRAP_WIDTH)
      window = text_box(app, lines, fit(lines, CONFIRM_MIN_WIDTH), title)
      pair(window, Widgets::Button.new(label: '&Yes', on_click: closer(app, window) { on_yes&.call }),
           Widgets::Button.new(label: '&No', on_click: closer(app, window) { on_no&.call }), BUTTON_WIDTH)
      show(app, window)
    end

    # Opens a box with +prompt+, a text field holding +value+, and OK and
    # Cancel buttons. OK, or Enter in the field, closes the box and calls
    # +on_submit+ with the entered text; Cancel only closes it. The field
    # has the focus.
    #
    # Returns the Window.
    def self.input(app, prompt:, title: ' Input ', value: '', width: INPUT_WIDTH, on_submit: nil)
      window = centred_window(app, width: width, height: INPUT_HEIGHT, title: title)
      inner  = window.bounds.width - (2 * PADDING)
      place(window, Widgets::Label.new(text: prompt, style_key: :window_text), PADDING, TEXT_TOP, inner)
      field = Widgets::TextInput.new(value: value)
      field.on_submit = closer(app, window) { on_submit&.call(field.value) }
      place(window, field, PADDING, INPUT_ROW, inner)
      pair(window, Widgets::Button.new(label: '&OK', on_click: field.on_submit),
           Widgets::Button.new(label: '&Cancel', on_click: closer(app, window)), CANCEL_WIDTH)
      show(app, window, focus: field)
    end

    # A callable for a button or a field: it closes +window+ on +app+,
    # then calls the block. It returns +:handled+.
    def self.closer(app, window, &after)
      lambda do |*|
        app.close_window(window)
        after&.call
        :handled
      end
    end

    # +text+ word-wrapped to +width+, its line ends and runs of blanks
    # taken as single spaces.
    def self.wrap(text, width) = FrameBuffer.wrap_ansi(text.to_s.split.join(' '), width)

    # The width of a box around +lines+: the longest and TEXT_CHROME, at
    # least +min+.
    def self.fit(lines, min) = [(lines.map(&:length).max || 0) + TEXT_CHROME, min].max

    # A centred window of +width+ with +lines+ as labels and room under
    # them for the buttons.
    def self.text_box(app, lines, width, title)
      window = centred_window(app, width: width, height: lines.size + CHROME_ROWS, title: title)
      lines.each_with_index do |line, i|
        label = Widgets::Label.new(text: line, style_key: :window_text)
        place(window, label, PADDING, TEXT_TOP + i, window.bounds.width - (2 * PADDING))
      end
      window
    end

    # Lays +widget+ out in +window+ at column +col+ and row +row+ of it
    # (from 0), +width+ wide and one row high, and adds it.
    def self.place(window, widget, col, row, width)
      widget.layout(window.bounds.x + col, window.bounds.y + row, width, 1)
      window.add(widget)
    end

    # Places the buttons +left+ (BUTTON_WIDTH wide) and +right+ (+width+
    # wide) side by side round the middle of the button row.
    def self.pair(window, left, right, width)
      middle = window.bounds.width / 2
      place(window, left, middle - HALF_GAP - BUTTON_WIDTH, button_row(window), BUTTON_WIDTH)
      place(window, right, middle + HALF_GAP, button_row(window), width)
    end

    # The row of the buttons in +window+.
    def self.button_row(window) = window.bounds.height - BUTTON_ROW

    # Opens +window+ on +app+ with the focus on its first widget, or on
    # +focus+. Returns the window.
    def self.show(app, window, focus: nil)
      window.reset_focus
      window.focus_manager.focus(focus) if focus
      app.open_window(window)
      window
    end

    private_class_method :closer, :wrap, :fit, :text_box, :place, :pair, :button_row, :show
  end
end
