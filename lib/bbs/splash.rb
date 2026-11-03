# frozen_string_literal: true

module BBS
  # A screen between the terminal question (BBS::Terminal) and the board: a
  # drawing of the board's for each face, centred, a prompt under it, and a
  # wait for a key. The board brings the drawings, two BBS::Art: a modern
  # terminal gets the one for ANSI (#ansi_lines), a Commodore 64 a
  # +petscii-upper+ one on a BBS::Petscii::Canvas.
  #
  #   SPLASH = BBS::Splash.new(modern: BBS::Art.load('art/logo-modern.yml'),
  #                            petscii: BBS::Art.load('art/logo-c64.yml'))
  #   BBS.configure { |c| c.flow = BBS::Terminal.flow(title: 'My board', modern: M, petscii: P, splash: SPLASH) }
  class Splash
    # The default line under the drawing.
    PROMPT = 'PRESS ANY KEY TO CONTINUE'
    # Seconds to wait for the key; nothing within them continues too.
    WAIT = 60

    # The drawing for a modern terminal, a BBS::Art.
    attr_reader :modern
    # The drawing for a C64, a +petscii-upper+ BBS::Art.
    attr_reader :petscii
    # The line under the drawing, plain ASCII capitals (both machines print
    # them alike).
    attr_reader :prompt

    # A splash of the drawings +modern+ and +petscii+ (BBS::Art), with
    # +prompt+ under them. Raises ArgumentError when +petscii+ is not a
    # +petscii-upper+ art, or a drawing with the prompt is higher than the
    # C64's 25 rows.
    def initialize(modern:, petscii:, prompt: PROMPT)
      raise ArgumentError, 'the C64 drawing of a splash must be petscii-upper' unless petscii.petscii?
      raise ArgumentError, 'a splash drawing is at most 24 rows high' if [modern.rows, petscii.rows].max >= Petscii::ROWS

      @modern  = modern
      @petscii = petscii
      @prompt  = prompt
    end

    # Shows the drawing of +face+ (+:modern+ or +:petscii+) on +session+ and
    # waits for a key (or WAIT seconds). A C64 gets its lowercase set back
    # and a clear screen afterwards, as BBS::Telnet#petscii! left it; a
    # modern terminal a clear screen. A modern terminal narrower than the
    # drawing gets no splash.
    #
    # Returns whether the call goes on: +false+ when the line dropped.
    def continue?(session, face)
      if face == :petscii
        show_petscii(session)
      elsif session.term_cols >= @modern.cols
        show_modern(session)
      else
        return true
      end
      key = session.readkey(timeout: WAIT)
      session.write_raw(Petscii.bytes("#{Petscii::LOWERCASE}#{Petscii::CLEAR}")) if face == :petscii
      session.write("#{Ansi::SHOW_CURSOR}#{Ansi::CLEAR}") if face == :modern && key
      !key.nil?
    end

    private

    # The drawing and the prompt in the middle of the window, the cursor
    # hidden.
    def show_modern(session)
      top   = [(session.term_rows.to_i - @modern.rows - 1) / 2, 0].max
      lines = @modern.ansi_lines.map { |line| centred(session, @modern.cols, line) }
      lines << centred(session, @prompt.size, "#{Ansi::GREY}#{@prompt}#{Ansi::RESET}")
      session.write("#{Ansi::HIDE_CURSOR}#{Ansi::CLEAR}#{Ansi::CRLF * top}#{lines.join(Ansi::CRLF)}")
    end

    def centred(session, width, text) = "#{' ' * ((session.term_cols - width) / 2)}#{text}"

    # The drawing at the top in the middle, the prompt on the last row.
    def show_petscii(session)
      canvas = @petscii.draw_canvas(Petscii::Canvas.new, col: (Petscii::COLS - @petscii.cols) / 2)
      canvas.text(Petscii::ROWS - 1, (Petscii::COLS - @prompt.size) / 2, @prompt, :light_grey)
      session.write_raw(canvas.frame)
    end
  end
end
