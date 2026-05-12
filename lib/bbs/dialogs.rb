# frozen_string_literal: true

require_relative 'window'
require_relative 'widgets'

module BBS
  module Dialogs
    # Build a centred Window with the given inner size.
    def self.centred_window(app, width:, height:, title: nil)
      cols  = app.cols
      rows  = app.rows
      w     = [width, cols - 4].min
      h     = [height, rows - 4].min
      x     = (cols - w) / 2 + 1
      y     = (rows - h) / 2 + 1
      win   = Window.new(title: title, modal: true)
      win.layout(x, y, w, h)
      win
    end

    # Show a one-line message with an OK button.
    def self.message(app, text, title: ' Message ', width: nil)
      lines  = wrap(text, 50)
      w      = (width || ([lines.map(&:length).max + 6, 30].max))
      h      = lines.size + 5
      window = centred_window(app, width: w, height: h, title: title)

      lines.each_with_index do |line, i|
        label = Widgets::Label.new(text: line, style_key: :window_text)
        label.layout(window.bounds.x + 2, window.bounds.y + 1 + i, w - 4, 1)
        window.add(label)
      end

      btn = Widgets::Button.new(label: '&OK', on_click: ->(_) { app.close_window(window) })
      btn.layout(window.bounds.x + (w - 8) / 2, window.bounds.y + h - 2, 8, 1)
      window.add(btn)
      window.reset_focus
      app.open_window(window)
      window
    end

    # Yes/No confirmation. Calls on_yes / on_no.
    def self.confirm(app, text, title: ' Confirm ', on_yes: nil, on_no: nil)
      lines = wrap(text, 50)
      w     = [lines.map(&:length).max + 6, 36].max
      h     = lines.size + 5
      window = centred_window(app, width: w, height: h, title: title)

      lines.each_with_index do |line, i|
        label = Widgets::Label.new(text: line, style_key: :window_text)
        label.layout(window.bounds.x + 2, window.bounds.y + 1 + i, w - 4, 1)
        window.add(label)
      end

      yes = Widgets::Button.new(label: '&Yes',
                                on_click: ->(_) { app.close_window(window); on_yes&.call })
      no  = Widgets::Button.new(label: '&No',
                                on_click: ->(_) { app.close_window(window); on_no&.call })
      yes.layout(window.bounds.x + w / 2 - 9, window.bounds.y + h - 2, 8, 1)
      no.layout(window.bounds.x + w / 2 + 1,  window.bounds.y + h - 2, 8, 1)
      window.add(yes)
      window.add(no)
      window.reset_focus
      app.open_window(window)
      window
    end

    # Single-line text input dialog. Calls on_submit with the entered value.
    def self.input(app, prompt:, title: ' Input ', value: '', width: 50, on_submit: nil)
      w      = width
      h      = 7
      window = centred_window(app, width: w, height: h, title: title)

      label = Widgets::Label.new(text: prompt, style_key: :window_text)
      label.layout(window.bounds.x + 2, window.bounds.y + 1, w - 4, 1)
      window.add(label)

      input = Widgets::TextInput.new(value: value)
      input.layout(window.bounds.x + 2, window.bounds.y + 3, w - 4, 1)
      window.add(input)

      ok = Widgets::Button.new(label: '&OK',
                               on_click: ->(_) { app.close_window(window); on_submit&.call(input.value) })
      cancel = Widgets::Button.new(label: '&Cancel',
                                   on_click: ->(_) { app.close_window(window) })
      ok.layout(window.bounds.x + w / 2 - 9,     window.bounds.y + h - 2, 8, 1)
      cancel.layout(window.bounds.x + w / 2 + 1, window.bounds.y + h - 2, 10, 1)
      window.add(ok)
      window.add(cancel)
      window.reset_focus
      window.focus_manager.focus(input)
      app.open_window(window)
      window
    end

    def self.wrap(text, width)
      words = text.to_s.split
      lines = []
      cur   = +''
      words.each do |w|
        if cur.empty?
          cur << w
        elsif cur.length + 1 + w.length <= width
          cur << ' ' << w
        else
          lines << cur.dup
          cur = +w
        end
      end
      lines << cur unless cur.empty?
      lines
    end
  end
end
