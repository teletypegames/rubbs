# frozen_string_literal: true

require_relative 'wording'
require_relative 'modern/guestbook_windows'

module UI
  # The board on a modern terminal: the guestbook in a two-pane window, and
  # a form to sign it.
  module Modern
    TITLE = ['█▀▀ █▀█ █▀▄▀█ █▀█ █   █▀▀', '▀▀█ █▀█ █ ▀ █ █▀▀ █   █▀▀', '▀▀▀ ▀ ▀ ▀   ▀ ▀   ▀▀▀ ▀▀▀'].freeze

    APP = BBS::Application.define do
      theme :synchronet

      command(:read, 'Read the guestbook', key: 'F2', hint: 'Read') { show(:entries) }
      command(:sign, 'Sign…', key: 'F3') { show(:sign) }
      menu 'Guestbook', :read, :sign, :separator, :log_off
      help about: Wording::ABOUT

      status { "#{guestbook.all.size} entries" }

      desktop do
        art  TITLE, top: 2
        line 'F2 read · F3 sign · Alt-X log off', bottom: 1
        on_show { show(:entries) }
      end

      parts GuestbookWindows
    end
  end
end
