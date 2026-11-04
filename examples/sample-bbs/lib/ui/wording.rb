# frozen_string_literal: true

module UI
  # What both faces tell the caller.
  module Wording
    ABOUT = 'Sample BBS — the sample board of rubbs: a guestbook on a modern terminal and on a Commodore 64. ' \
            'Read what callers wrote, and sign it yourself.'

    # The answers of GuestbookService#sign.
    SIGN = {
      ok:       'Thank you for signing the guestbook.',
      no_name:  'Sign with a name, please.',
      empty:    'Write something first.',
      too_long: 'That is too long for the guestbook.'
    }.freeze
  end
end
