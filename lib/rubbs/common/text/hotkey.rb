# frozen_string_literal: true

module Rubbs
  module Common
    module Text
      # The hotkey of a label such as <tt>&File</tt>: the letter after the
      # <tt>&</tt>. Buttons, menus and menu items mark their hotkeys this way.
      #
      #   Rubbs::Common::Text::Hotkey.letter('E&xit')   # => "x"
      #   Rubbs::Common::Text::Hotkey.split('E&xit')    # => ["E", "x", "it"]
      #   Rubbs::Common::Text::Hotkey.plain('E&xit')    # => "Exit"
      module Hotkey
        module_function

        # The label round its hotkey: <tt>[before, letter, after]</tt>, or
        # +nil+ when +label+ marks none.
        def split(label)
          idx = label.index('&')
          return nil unless idx && idx + 1 < label.length

          [label[0, idx], label[idx + 1], label[(idx + 2)..]]
        end

        # The hotkey letter of +label+, downcased, or +nil+.
        def letter(label) = split(label)&.[](1)&.downcase

        # +label+ without its <tt>&</tt> marker.
        def plain(label) = label.sub('&', '')
      end
    end
  end
end
