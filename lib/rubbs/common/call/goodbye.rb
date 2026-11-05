# frozen_string_literal: true

module Rubbs
  module Common
    module Call
      # The last screen of a call: thanks for calling, a note, where to find
      # more of the board's family and its QR code (Rubbs::Common::Text::QR), and NO CARRIER.
      # The board's name, the address and the QR code come from Rubbs.config
      # (+title+ and the Rubbs::Common::Board::Preset); a board that uses Rubbs.board only says
      # <tt>goodbye 'a note'</tt>. Each face writes its own: a modern terminal
      # in one write (Rubbs::Modern::Goodbye), a C64 a reversed bar, then the
      # modem's <tt>+++</tt>, <tt>ATH0</tt> and NO CARRIER a moment apart
      # (Rubbs::Petscii::Goodbye). This module picks the face and holds what
      # both say.
      #
      #   Rubbs::Common::Call::Goodbye.show(session, note: "The stories are their publishers'.")
      module Goodbye
        # What the goodbye says before the board's name.
        GREETING = 'Thanks for calling'
        # The most lines the QR code may take; an address that needs more
        # goes without one.
        QR_ROWS = 15

        # The goodbye of the face of +session+: Rubbs::Petscii::Goodbye.show on a
        # PETSCII line, Rubbs::Modern::Goodbye.show otherwise, with the board's
        # title and preset. +note+ is the board's own line (its sources, its
        # licence); +clear+ (modern: whether the screen is cleared first),
        # +color+, +bar+ and +art+ (C64: the bar's colour and text, lines under
        # it) are those of the faces, +greeting+ what both say before the
        # board's name. A dropped line is not an error here: the caller has
        # gone already.
        #
        # Returns +nil+.
        def self.show(session, note: nil, clear: true, color: Petscii::Colors::CY, bar: nil, art: nil, greeting: GREETING)
          if session.respond_to?(:petscii?) && session.petscii?
            Petscii::Goodbye.show(session, note: note, color: color, bar: bar, art: art, greeting: greeting)
          else
            Modern::Goodbye.show(session, note: note, clear: clear, greeting: greeting)
          end
        rescue *Line::LINE_DROPPED
          nil
        end

        # The words after the greeting: +note+ (when given) and "More of us:
        # +url+" (when given), on one line.
        def self.more_text(note, url) = [note, ("More of us: #{url}" if url)].compact.join(' ')

        # The lines the block draws of the QR code of +qr+; none for +nil+ or an
        # address too long (Rubbs::Common::Text::QR::TooLong).
        def self.qr_lines(qr)
          qr.nil? ? [] : yield(qr)
        rescue Text::QR::TooLong
          []
        end
      end
    end
  end
end
