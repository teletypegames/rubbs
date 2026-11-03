# frozen_string_literal: true

module BBS
  # The Teletype Games logo after the terminal question (BBS::Terminal), on
  # a screen of its own with PRESS ANY KEY TO CONTINUE under it, centred.
  # The logo is two BBS::Art drawings made from the same pixels, the logo
  # halved: a modern terminal gets 66 × 23 half blocks in 256 colours
  # (<tt>splash/ttg-modern.yml</tt>), a Commodore 64 33 × 23 quarter blocks
  # in its own colours (<tt>splash/ttg-c64.yml</tt>), a colour a cell.
  #
  #   BBS.configure { |c| c.flow = BBS::Terminal.flow(title: 'My board', modern: M, petscii: P, splash: true) }
  module Splash
    # The folder of the drawings.
    DIR = File.join(__dir__, 'splash')
    # The line under the logo.
    PROMPT = 'PRESS ANY KEY TO CONTINUE'
    # Seconds to wait for the key; nothing within them continues too.
    WAIT = 60

    # The drawing of +face+ (+:modern+ or +:petscii+), a BBS::Art, loaded
    # once.
    def self.art(face)
      @arts ||= {}
      @arts[face] ||= Art.load(File.join(DIR, face == :petscii ? 'ttg-c64.yml' : 'ttg-modern.yml'))
    end

    # Shows the logo on +session+ in its +face+ and waits for a key (or
    # WAIT seconds). A C64 gets its lowercase set back and a clear screen
    # afterwards, as BBS::Telnet#petscii! left it; a modern terminal a clear
    # screen. A modern terminal narrower than the logo gets no logo.
    #
    # Returns whether the call goes on: +false+ when the line dropped.
    def self.continue?(session, face)
      if face == :petscii
        petscii(session)
      elsif session.term_cols >= art(:modern).cols
        modern(session)
      else
        return true
      end
      key = session.readkey(timeout: WAIT)
      session.write_raw(Petscii.bytes("#{Petscii::LOWERCASE}#{Petscii::CLEAR}")) if face == :petscii
      session.write("#{Ansi::SHOW_CURSOR}#{Ansi::CLEAR}") if face == :modern && key
      !key.nil?
    end

    # Writes the modern screen: the logo and the prompt in the middle of
    # the window, the cursor hidden.
    def self.modern(session)
      art   = art(:modern)
      top   = [(session.term_rows.to_i - art.rows - 1) / 2, 0].max
      lines = art.ansi_lines.map { |line| centred(session, art.cols, line) }
      lines << centred(session, PROMPT.size, "#{Ansi::GREY}#{PROMPT}#{Ansi::RESET}")
      session.write("#{Ansi::HIDE_CURSOR}#{Ansi::CLEAR}#{Ansi::CRLF * top}#{lines.join(Ansi::CRLF)}")
    end
    private_class_method :modern

    # +text+, +width+ columns wide, after the spaces that centre it in the
    # window of +session+.
    def self.centred(session, width, text) = "#{' ' * ((session.term_cols - width) / 2)}#{text}"
    private_class_method :centred

    # Writes the C64 screen: the logo at the top in the middle, the prompt
    # on the last row.
    def self.petscii(session)
      art    = art(:petscii)
      canvas = art.draw_canvas(Petscii::Canvas.new, col: (Petscii::COLS - art.cols) / 2)
      canvas.text(Petscii::ROWS - 1, (Petscii::COLS - PROMPT.size) / 2, PROMPT, :light_grey)
      session.write_raw(canvas.frame)
    end
    private_class_method :petscii
  end
end
