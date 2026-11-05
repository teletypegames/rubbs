# frozen_string_literal: true

module Rubbs
  module Common
    module Call
      # A screen between the terminal question (Rubbs::Common::Call::Terminal) and the board: a
      # drawing of the board's for each face, centred, a prompt under it, and a
      # wait for a key. The board brings the drawings, two Rubbs::Common::Art; each
      # face draws its own (Rubbs::Modern::Splash in ANSI, Rubbs::Petscii::Splash a
      # +petscii-upper+ one on a Rubbs::Petscii::Canvas), this class waits and asks.
      #
      # On a board with a login (Rubbs::Common::Auth) a caller who is not logged in is
      # asked instead of the prompt: <tt>Login | Register | Guest</tt>, each
      # word's first letter its key, in their own colour. L and R open the
      # caller's profile (Rubbs::Common::Auth::Profile) at a login or a new account; G
      # (and the wait running out) goes on as a guest.
      #
      #   SPLASH = Rubbs::Common::Call::Splash.new(modern: Rubbs::Common::Art.load('art/logo-modern.yml'),
      #                            petscii: Rubbs::Common::Art.load('art/logo-c64.yml'))
      #   Rubbs.configure { |c| c.flow = Rubbs::Common::Call::Terminal.flow(title: 'My board', modern: M, petscii: P, splash: SPLASH) }
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
        # Rubbs::Petscii::Canvas colours on a C64.
        COLORS = { text: Modern::Ansi::WHITE, key: Modern::Ansi::BRIGHT_GREEN, c64_text: :white, c64_key: :light_green }.freeze

        # The drawing for a modern terminal, a Rubbs::Common::Art.
        attr_reader :modern
        # The drawing for a C64, a +petscii-upper+ Rubbs::Common::Art.
        attr_reader :petscii
        # The line under the drawing, plain ASCII capitals (both machines print
        # them alike).
        attr_reader :prompt
        # The choices of a board with a login (see CHOICES), or +nil+ for the
        # plain prompt everywhere.
        attr_reader :choices
        # The colours of the choices (COLORS with the board's own).
        attr_reader :colors

        # A splash of the drawings +modern+ and +petscii+ (Rubbs::Common::Art), with
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
        # Rubbs::Common::Line::Telnet#petscii! left it; a modern terminal a clear screen. A
        # modern terminal narrower than the drawing gets no splash.
        #
        # Returns whether the call goes on: +false+ when the line dropped.
        def continue?(session, face)
          asks    = asks?(session)
          painter = face == :petscii ? Petscii::Splash.new(self) : Modern::Splash.new(self)
          return true unless painter.fits?(session)

          painter.show(session, asks)

          key = asks ? choose(session) : session.readkey(timeout: WAIT)
          painter.leave(session, key)
          return false if key.nil?

          open_profile(session, key)
          true
        end

        # The words and keys of the choices for a face to draw:
        # <tt>[text, :key or :text]</tt> runs.
        def choice_runs
          @choices.each_with_index.flat_map do |(word, _), i|
            [*([[BETWEEN, :text]] unless i.zero?), [word[0], :key], [word[1..], :text]]
          end
        end

        # The columns the choices take.
        def choice_width = choice_runs.sum { |text, _| text.length }

        # Whether the splash asks the caller on +session+ to log in: the board
        # has a login and choices, and the caller is not logged in.
        def asks?(session)
          return false unless @choices && Rubbs.config.auth

          !(session.respond_to?(:identity) && session.identity.signed_in?)
        end

        private

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
      end
    end
  end
end
