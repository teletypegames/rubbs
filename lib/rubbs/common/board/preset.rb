# frozen_string_literal: true

module Rubbs
  module Common
    module Board
      # What a family of boards has in common and rubbs does not know: the
      # splash before the first screen, the address on the goodbye screen, the
      # QR code under it and the User-Agent of the board's HTTP requests. A
      # board picks one with <tt>preset</tt> in Rubbs.board; without one it gets
      # NONE.
      #
      #   TTG_PRESET = Rubbs::Common::Board::Preset.new(splash: TTG::Logo.splash, url: 'teletypegames.org',
      #                                qr: 'HTTPS://TELETYPEGAMES.ORG', user_agent: '(+https://teletypegames.org)')
      #
      # [splash]     a Rubbs::Common::Call::Splash shown after the terminal question, or +nil+
      # [url]        the "More of us:" address of the goodbye screen, or +nil+
      # [qr]         the text of the goodbye screen's QR code, or +nil+ for none
      # [user_agent] what follows <tt>rubbs/<version></tt> in the User-Agent of
      #              Rubbs::Common::Web::HTTP, or +nil+
      # [profile]    the look of the caller's profile (a
      #              Rubbs::Common::Auth::Profile::Look: the drawing over it, the title,
      #              the words, the colours), or +nil+ for the plain one
      Preset = Data.define(:splash, :url, :qr, :user_agent, :profile) do
        # Creates a preset; every part is optional.
        def initialize(splash: nil, url: nil, qr: nil, user_agent: nil, profile: nil) = super
      end

      # The preset of a board without one.
      class Preset
        # The preset of a board that picks none: no splash, no address, no QR code.
        NONE = new
      end
    end
  end
end
