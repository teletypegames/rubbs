# frozen_string_literal: true

module BBS
  module Petscii
    class Face
      # What a face tells the caller beyond the screen's own sentences: a
      # failure that ends the item, a wait, a domain result in words; and the
      # doors and rate-limit key of the call.
      module Sayings
        include Colors

        # Runs the sub-menu +name+ (Face.sub_menu) until the caller takes its
        # back item or presses ←. A BBS::Abort in an item leaves them at it.
        def sub_menu(name)
          menu = self.class.sub_menus.fetch(name)
          loop do
            break if menu.take(self) == :log_off
          rescue Abort
            next
          end
          nil
        end

        # Says +text+ in red (or +color+), waits, and ends what the caller
        # started (raises BBS::Abort).
        def fail_with(text, color: RD)
          alert(text, color: color)
          raise Abort, text
        end

        # Says +text+ dimmed, runs the block and returns its value; with
        # +failed+, a +nil+ value or an error says +failed+ (#fail_with).
        def loading(text = 'working…', failed: nil)
          say(text, color: GR)
          value = yield
          fail_with(failed) if failed && value.nil?
          value
        rescue Abort, *LINE_DROPPED
          raise
        rescue StandardError => e
          raise unless failed

          BBS.log('loading', e)
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

        # Hands the line to +door+ (a BBS::Door) and back.
        def open_door(door) = door.run(@session, @context)

        # The key the caller is known by for rate limits.
        def caller_key = @session.caller_key
      end
    end
  end
end
