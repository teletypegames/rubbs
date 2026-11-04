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
      item('l', 'log in', 'your account', if: -> { !signed_in? }) { log_in }
      item('n', 'new account', 'a name and a password', if: -> { !signed_in? }) { register }
      item('o', 'log out', -> { identity.name.to_s }, if: -> { signed_in? }) { log_out }
      log_off
    end

    private

    def read
      each_pick('GUESTBOOK', -> { guestbook.all }, label: ->(e) { "#{e.day} #{e.name}" }) do |entry|
        page(entry.name.upcase[0, 30], [" #{GR}#{entry.day}#{LG}", '', *wrap(entry.text).map { |l| " #{l}" }])
      end
    end

    def register
      title('NEW ACCOUNT')
      name = prompt('name', max: 20) or return
      password = prompt('password', mask: '*', max: 200) or return
      found = directory.register(name, password, prompt('again', mask: '*', max: 200).to_s)
      return alert(Wording::REGISTER.fetch(found)) unless found.is_a?(BBS::Auth::Identity)

      @session.identity = found
      notice("Welcome, #{found.name}.")
    end

    def sign
      title('SIGN THE GUESTBOOK')
      name = identity.name || prompt('name', max: 30) or return
      text = prompt('text', max: 200) or return
      report(guestbook.sign(name, text), Wording::SIGN)
    end
  end
end
