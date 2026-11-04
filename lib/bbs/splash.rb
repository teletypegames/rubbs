# frozen_string_literal: true

module BBS
  # A screen between the terminal question (BBS::Terminal) and the board: a
  # drawing of the board's for each face, centred, a prompt under it, and a
  # wait for a key. The board brings the drawings, two BBS::Art: a modern
  # terminal gets the one for ANSI (#ansi_lines), a Commodore 64 a
  # +petscii-upper+ one on a BBS::Petscii::Canvas.
  #
  # On a board with a login (BBS::Auth) a caller who is not logged in is
  # asked instead of the prompt: <tt>Login | Register | Guest</tt>, each
  # word's first letter its key, in their own colour. L and R open the
  # caller's profile (BBS::Auth::Profile) at a login or a new account; G
  # (and the wait running out) goes on as a guest.
  #
  #   SPLASH = BBS::Splash.new(modern: BBS::Art.load('art/logo-modern.yml'),
  #                            petscii: BBS::Art.load('art/logo-c64.yml'))
  #   BBS.configure { |c| c.flow = BBS::Terminal.flow(title: 'My board', modern: M, petscii: P, splash: SPLASH) }
  class Splash
    # The default line under the drawing.
    PROMPT = 'PRESS ANY KEY TO CONTINUE'
    # Seconds to wait for the key; nothing within them continues too.
    WAIT = 60
    # The choices of a board with a login: the word, its key (the first
    # letter), and what the profile starts with (+nil+: go on as a guest).
    CHOICES = [['Login', :log_in], ['Register', :register], ['Guest', nil]].freeze
    # What stands between two choices.
    BETWEEN = ' | '
    # The colours of the choices' words and keys: ANSI on a modern terminal,
    # BBS::Petscii::Canvas colours on a C64.
    COLORS = { text: Ansi::WHITE, key: Ansi::BRIGHT_GREEN, c64_text: :white, c64_key: :light_green }.freeze

    # The drawing for a modern terminal, a BBS::Art.
    attr_reader :modern
    # The drawing for a C64, a +petscii-upper+ BBS::Art.
    attr_reader :petscii
    # The line under the drawing, plain ASCII capitals (both machines print
    # them alike).
    attr_reader :prompt
    # The choices of a board with a login (see CHOICES), or +nil+ for the
    # plain prompt everywhere.
    attr_reader :choices

    # A splash of the drawings +modern+ and +petscii+ (BBS::Art), with
    # +prompt+ under them; +choices+ (CHOICES by default, +nil+ for none)
    # replace it on a board with a login, in +colors+ (over COLORS). Raises
    # ArgumentError when +petscii+ is not a +petscii-upper+ art, or a
    # drawing with the prompt is higher than the C64's 25 rows.
    def initialize(modern:, petscii:, prompt: PROMPT, choices: CHOICES, colors: {})
      raise ArgumentError, 'the C64 drawing of a splash must be petscii-upper' unless petscii.petscii?
      raise ArgumentError, 'a splash drawing is at most 24 rows high' if [modern.rows, petscii.rows].max >= Petscii::ROWS

      @modern  = modern
      @petscii = petscii
      @prompt  = prompt
      @choices = choices
      @colors  = COLORS.merge(colors)
    end

    # Shows the drawing of +face+ (+:modern+ or +:petscii+) on +session+ and
    # waits for a key (or WAIT seconds); on a board with a login, for a
    # choice (#asks?), and L or R open the caller's profile there. A C64
    # gets its lowercase set back and a clear screen afterwards, as
    # BBS::Telnet#petscii! left it; a modern terminal a clear screen. A
    # modern terminal narrower than the drawing gets no splash.
    #
    # Returns whether the call goes on: +false+ when the line dropped.
    def continue?(session, face)
      asks = asks?(session)
      return true unless show(session, face, asks)

      key = asks ? choose(session) : session.readkey(timeout: WAIT)
      session.write_raw(Petscii.bytes("#{Petscii::LOWERCASE}#{Petscii::CLEAR}")) if face == :petscii
      session.write("#{Ansi::SHOW_CURSOR}#{Ansi::CLEAR}") if face == :modern && key
      return false if key.nil?

      open_profile(session, key)
      true
    end

    # Whether the splash asks the caller on +session+ to log in: the board
    # has a login and choices, and the caller is not logged in.
    def asks?(session)
      return false unless @choices && BBS.config.auth

      !(session.respond_to?(:identity) && session.identity.signed_in?)
    end

    private

    # Shows the splash of +face+; false when a modern terminal is too
    # narrow for the drawing (and nothing is shown).
    def show(session, face, asks)
      return show_petscii(session, asks) || true if face == :petscii
      return false if session.term_cols < @modern.cols

      show_modern(session, asks)
      true
    end

    # The key of a choice, or the wait running out (as Guest); +nil+ when
    # the line dropped. Other keys are not taken.
    def choose(session)
      keys = @choices.to_h { |word, start| [word[0].downcase, start || :guest] }
      loop do
        key = session.readkey(timeout: WAIT)
        return key if key.nil?
        return :guest if key == :idle

        found = keys[key.to_s.downcase]
        return found if found
      end
    end

    # The caller's profile at a login or a new account, for a key that asks
    # for one.
    def open_profile(session, key)
      Auth::Profile.run(session, start: key) if %i[log_in register].include?(key)
    end

    # The words and keys of the choices: <tt>[text, :key or :text]</tt> runs.
    def choice_runs
      @choices.each_with_index.flat_map do |(word, _), i|
        [*([[BETWEEN, :text]] unless i.zero?), [word[0], :key], [word[1..], :text]]
      end
    end

    def choice_width = choice_runs.sum { |text, _| text.length }

    # The drawing and the prompt (or the choices) in the middle of the
    # window, the cursor hidden.
    def show_modern(session, asks)
      top   = [(session.term_rows.to_i - @modern.rows - 1) / 2, 0].max
      lines = @modern.ansi_lines.map { |line| centred(session, @modern.cols, line) }
      lines << (asks ? modern_choices(session) : centred(session, @prompt.size, "#{Ansi::GREY}#{@prompt}#{Ansi::RESET}"))
      session.write("#{Ansi::HIDE_CURSOR}#{Ansi::CLEAR}#{Ansi::CRLF * top}#{lines.join(Ansi::CRLF)}")
    end

    def modern_choices(session)
      text = choice_runs.map { |part, role| "#{@colors[role]}#{part}" }.join
      centred(session, choice_width, "#{text}#{Ansi::RESET}")
    end

    def centred(session, width, text) = "#{' ' * ((session.term_cols - width) / 2)}#{text}"

    # The drawing at the top in the middle, the prompt (or the choices) on
    # the last row.
    def show_petscii(session, asks)
      canvas = @petscii.draw_canvas(Petscii::Canvas.new, col: (Petscii::COLS - @petscii.cols) / 2)
      asks ? petscii_choices(canvas) : canvas.text(Petscii::ROWS - 1, (Petscii::COLS - @prompt.size) / 2, @prompt, :light_grey)
      session.write_raw(canvas.frame)
    end

    # The choices in capitals (the drawing's character set has no small
    # letters, and no |: a line glyph stands for it), each key in its
    # colour.
    def petscii_choices(canvas)
      col = (Petscii::COLS - choice_width) / 2
      choice_runs.each do |text, role|
        canvas.text(Petscii::ROWS - 1, col, text.upcase.tr('|', '│'), @colors[:"c64_#{role}"])
        col += text.length
      end
    end
  end
end
