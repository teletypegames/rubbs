# frozen_string_literal: true

require_relative 'wording'

module UI
  # The board on a Commodore 64: the guestbook as a list, a line to sign it.
  class Petscii < BBS::Petscii::Face
    title('SAMPLE BBS') { "#{guestbook.all.size} entries" }

    masthead do
      gap
      logo 'SAMPLE', colors: [CY, CY, LB, LB, BL]
      gap
      line 'the guestbook of rubbs', color: WH
      rule
    end

    main_menu do
      item('r', 'read the guestbook', -> { "#{guestbook.all.size} entries" }) { read }
      item('s', 'sign it', 'your name and a line') { sign }
      item('a', 'about', 'this board') { page('ABOUT', wrap(Wording::ABOUT).map { |l| " #{l}" }) }
      log_off
    end

    private

    def read
      each_pick('GUESTBOOK', -> { guestbook.all }, label: ->(e) { "#{e.day} #{e.name}" }) do |entry|
        page(entry.name.upcase[0, 30], [" #{GR}#{entry.day}#{LG}", '', *wrap(entry.text).map { |l| " #{l}" }])
      end
    end

    def sign
      title('SIGN THE GUESTBOOK')
      name = prompt('name', max: 30) or return
      text = prompt('text', max: 200) or return
      report(guestbook.sign(name, text), Wording::SIGN)
    end
  end
end
