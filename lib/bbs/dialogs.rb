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
      lines  = FrameBuffer.wrap_ansi(text.to_s.split.join(' '), width ? width - TEXT_CHROME : WRAP_WIDTH)
      w      = width || [(lines.map(&:length).max || 0) + TEXT_CHROME, MESSAGE_MIN_WIDTH].max
      h      = lines.size + CHROME_ROWS
      window = centred_window(app, width: w, height: h, title: title)
      w      = window.bounds.width
      h      = window.bounds.height

      lines.each_with_index do |line, i|
        label = Widgets::Label.new(text: line, style_key: :window_text)
        label.layout(window.bounds.x + PADDING, window.bounds.y + TEXT_TOP + i, w - (2 * PADDING), 1)
        window.add(label)
      end

      btn = Widgets::Button.new(label: '&OK', on_click: ->(_) { app.close_window(window) })
      btn.layout(window.bounds.x + ((w - BUTTON_WIDTH) / 2), window.bounds.y + h - BUTTON_ROW, BUTTON_WIDTH, 1)
      window.add(btn)
      window.reset_focus
      app.open_window(window)
      window
    end

    # Opens a Yes/No box with +text+. Each button closes the box, then calls
    # +on_yes+ or +on_no+ when given.
    #
    # Returns the Window.
    def self.confirm(app, text, title: ' Confirm ', on_yes: nil, on_no: nil)
      lines = FrameBuffer.wrap_ansi(text.to_s.split.join(' '), WRAP_WIDTH)
      w     = [(lines.map(&:length).max || 0) + TEXT_CHROME, CONFIRM_MIN_WIDTH].max
      h     = lines.size + CHROME_ROWS
      window = centred_window(app, width: w, height: h, title: title)
      w      = window.bounds.width
      h      = window.bounds.height

      lines.each_with_index do |line, i|
        label = Widgets::Label.new(text: line, style_key: :window_text)
        label.layout(window.bounds.x + PADDING, window.bounds.y + TEXT_TOP + i, w - (2 * PADDING), 1)
        window.add(label)
      end

      yes = Widgets::Button.new(label: '&Yes',
                                on_click: ->(_) { app.close_window(window); on_yes&.call })
      no  = Widgets::Button.new(label: '&No',
                                on_click: ->(_) { app.close_window(window); on_no&.call })
      yes.layout(window.bounds.x + (w / 2) - HALF_GAP - BUTTON_WIDTH, window.bounds.y + h - BUTTON_ROW, BUTTON_WIDTH, 1)
      no.layout(window.bounds.x + (w / 2) + HALF_GAP, window.bounds.y + h - BUTTON_ROW, BUTTON_WIDTH, 1)
      window.add(yes)
      window.add(no)
      window.reset_focus
      app.open_window(window)
      window
    end

    # Opens a box with +prompt+, a text field holding +value+, and OK and
    # Cancel buttons. OK, or Enter in the field, closes the box and calls
    # +on_submit+ with the entered text; Cancel only closes it. The field
    # has the focus.
    #
    # Returns the Window.
    def self.input(app, prompt:, title: ' Input ', value: '', width: INPUT_WIDTH, on_submit: nil)
      w      = width
      h      = INPUT_HEIGHT
      window = centred_window(app, width: w, height: h, title: title)
      w      = window.bounds.width
      h      = window.bounds.height

      label = Widgets::Label.new(text: prompt, style_key: :window_text)
      label.layout(window.bounds.x + PADDING, window.bounds.y + TEXT_TOP, w - (2 * PADDING), 1)
      window.add(label)

      # Enter in the field is the OK button.
      input  = nil
      submit = lambda do |_|
        app.close_window(window)
        on_submit&.call(input.value)
        :handled
      end
      input = Widgets::TextInput.new(value: value, on_submit: ->(_text, _field) { submit.call(nil) })
      input.layout(window.bounds.x + PADDING, window.bounds.y + INPUT_ROW, w - (2 * PADDING), 1)
      window.add(input)

      ok = Widgets::Button.new(label: '&OK', on_click: submit)
      cancel = Widgets::Button.new(label: '&Cancel',
                                   on_click: ->(_) { app.close_window(window) })
      ok.layout(window.bounds.x + (w / 2) - HALF_GAP - BUTTON_WIDTH, window.bounds.y + h - BUTTON_ROW, BUTTON_WIDTH, 1)
      cancel.layout(window.bounds.x + (w / 2) + HALF_GAP, window.bounds.y + h - BUTTON_ROW, CANCEL_WIDTH, 1)
      window.add(ok)
      window.add(cancel)
      window.reset_focus
      window.focus_manager.focus(input)
      app.open_window(window)
      window
    end
  end
end
