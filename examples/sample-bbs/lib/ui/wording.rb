# frozen_string_literal: true

module UI
  # What both faces tell the caller.
  module Wording
    ABOUT = 'Sample BBS — the sample board of rubbs: a guestbook on a modern terminal and on a Commodore 64. ' \
            'Read what callers wrote, and sign it yourself.'

    # The answers of Rubbs::Common::Auth::Directory#register.
    REGISTER = {
      invalid:     'A name is letters and digits, at most 20.',
      reserved:    'That name is kept for the board.',
      taken:       'That name has an account.',
      look_alike:  'That name looks too much like another one.',
      too_short:   'The password needs at least 6 characters.',
      mismatch:    'The two passwords differ.',
      busy:        'The board is busy. Try again in a moment.',
      unavailable: 'New accounts cannot be made right now.'
    }.freeze

    # The answers of GuestbookService#sign.
    SIGN = {
      ok:       'Thank you for signing the guestbook.',
      no_name:  'Sign with a name, please.',
      empty:    'Write something first.',
      too_long: 'That is too long for the guestbook.'
    }.freeze
  end
end
