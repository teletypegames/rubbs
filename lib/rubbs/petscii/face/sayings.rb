# frozen_string_literal: true

module Rubbs
  module Petscii
    class Face
      # What a face tells the caller beyond the screen's own sentences: a
      # failure that ends the item, a wait, a domain result in words; and the
      # doors and rate-limit key of the call.
      module Sayings
        include Colors

        # Runs the sub-menu +name+ (Face.sub_menu) until the caller takes its
        # back item or presses ←. A Rubbs::Common::Line::Abort in an item leaves them at it.
        def sub_menu(name)
          menu = self.class.sub_menus.fetch(name)
          loop do
            break if menu.take(self) == :log_off
          rescue Common::Line::Abort
            next
          end
          nil
        end

        # Says +text+ in red (or +color+), waits, and ends what the caller
        # started (raises Rubbs::Common::Line::Abort).
        def fail_with(text, color: RD)
          alert(text, color: color)
          raise Common::Line::Abort, text
        end

        # Says +text+ dimmed, runs the block and returns its value; with
        # +failed+, a +nil+ value or an error says +failed+ (#fail_with).
        def loading(text = 'working…', failed: nil)
          say(text, color: GR)
          value = yield
          fail_with(failed) if failed && value.nil?
          value
        rescue Common::Line::Abort, *Common::Line::LINE_DROPPED
          raise
        rescue StandardError => e
          raise unless failed

          Rubbs.log('loading', e)
          fail_with(failed)
        end

        # Tells the caller what +result+ (a Symbol a domain service answered)
        # means: its text in +messages+, green for +:ok+, red otherwise.
        # Returns +result+.
        def report(result, messages)
          text = messages[result]
          return result unless text

          result == :ok ? notice(text) : alert(text)
          result
        end

        # Hands the line to +door+ (a Rubbs::Common::Call::Door) and back.
        def open_door(door) = door.run(@session, @context)

        # The key the caller is known by for rate limits.
        def caller_key = @session.caller_key

        # The caller's profile (Rubbs::Common::Auth::Profile): log in, a new account,
        # the password, log out, until they go back. Returns +nil+.
        def open_profile = Common::Auth::Profile.run(@session)

        # Logs the caller in with the board's Rubbs::Common::Auth::Setup: a name and its
        # password as prompts (Rubbs::Common::Auth::Login), the outcome as an alert or
        # a notice. Returns the Rubbs::Common::Auth::Identity, or +nil+.
        def log_in
          setup = auth_setup or return alert(no_login)
          ask   = ->(label, mask: nil) { prompt(label, mask: mask, max: mask ? 200 : 20) }
          found = Common::Auth::Login.new(setup, @session, ask: ask, tell: ->(text) { alert(text) }).run
          notice("Welcome, #{found.name}.") if found
          found
        end
      end
    end
  end
end
