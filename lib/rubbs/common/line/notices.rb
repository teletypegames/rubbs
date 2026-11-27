# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      # One thing to tell the caller once, at the next screen: +text+ under
      # +title+ (see Notices).
      Notice = Data.define(:text, :title)

      # What a line keeps to tell its caller once, at the next screen: a
      # login the terminal sent that did not go (Rubbs::Common::Auth.from_line),
      # or anything a board notes before the first screen. A
      # Rubbs::Common::Screens::Pages runner shows them when it starts and
      # after every key (Rubbs::Common::Screens::Pages#show_notices), a
      # Rubbs::Modern::Application in a message box; a board shows nothing
      # by hand. Unlike Session#announce, which tells a running screen at
      # once, a notice waits for the screen.
      #
      #   session.notice('Your mailbox is full.', title: 'Mail')
      #   session.take_notices   # => [#<data Notice text="Your mailbox is full.", title="Mail">]
      module Notices
        # Keeps +text+ titled +title+ to tell the caller at the next screen.
        # Returns +nil+.
        def notice(text, title: 'Notice')
          (@notices ||= []) << Notice.new(text: text.to_s, title: title.to_s)
          nil
        end

        # The notices kept so far (Notice each, first first), taken: the
        # next call answers only the ones kept after. Asks the caller's
        # identity first, so the notice of a login the terminal sent with
        # the call is there.
        def take_notices
          identity if respond_to?(:identity)
          taken = @notices || []
          @notices = []
          taken
        end
      end
    end
  end
end
