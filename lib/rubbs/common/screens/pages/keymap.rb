# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      class Pages
        # The class-level DSL of a Rubbs::Common::Screens::Page and of a Rubbs::Common::Screens::Pages runner: the
        # keys it answers (#key) and what it does while the caller is silent
        # (#every). Both are inherited: a subclass's own keys are looked at
        # before its superclass's, so it can take a key over.
        #
        #   class ListPage < Rubbs::Common::Screens::Page
        #     key(:up)        { move(-1) }
        #     key('q', 'Q')   { back }
        #     key(/\A\d\z/)   { |digit| open(digit.to_i) }
        #     every(0.5)      { redraw }
        #   end
        module Keymap
          # One entry of the key map: the +matchers+ (a Symbol or String equal
          # to the key, or a Regexp matching a String key) and the +action+, a
          # block run in the instance with the key.
          Binding = Data.define(:matchers, :action) do
            # Whether +key+ is one of this binding's.
            def match?(key)
              matchers.any? { |m| m.is_a?(Regexp) ? key.is_a?(String) && m.match?(key) : m == key }
            end
          end

          # A timer of #every: its +seconds+ and its +action+.
          Timer = Data.define(:seconds, :action)

          # Binds +keys+ to the block: Symbols (<tt>:up</tt>, <tt>:enter</tt>,
          # <tt>:escape</tt> …, see Rubbs::Common::Line::Telnet#readkey), Strings (one
          # character each, case counts) or Regexps that match a String key.
          # The block runs in the instance (a Rubbs::Common::Screens::Page or the Rubbs::Common::Screens::Pages) with
          # the key as its argument; it can call +pass+ to leave the key to the
          # next binding. Returns the binding.
          def key(*keys, &action)
            raise ArgumentError, 'key needs a block' unless action

            own_keys << Binding.new(matchers: keys.flatten, action: action)
            own_keys.last
          end

          # Runs the block in the instance every +seconds+ while it is shown and
          # the caller is silent (an idle tick): a clock, a poll of something
          # that moves. Returns the timer.
          def every(seconds, &action)
            raise ArgumentError, 'every needs a block' unless action
            raise ArgumentError, "not a positive interval: #{seconds.inspect}" unless seconds.to_f.positive?

            own_timers << Timer.new(seconds: seconds.to_f, action: action)
            own_timers.last
          end

          # The bindings of the class and its ancestors, its own first.
          def keymap = own_keys + (superclass.respond_to?(:keymap) ? superclass.keymap : [])

          # The timers of the class and its ancestors.
          def timers = own_timers + (superclass.respond_to?(:timers) ? superclass.timers : [])

          private

          def own_keys = @own_keys ||= []

          def own_timers = @own_timers ||= []
        end

        # The instance side of Keymap: running the bindings of the class on a
        # key (#dispatch_key), and #pass to leave a key to the next one.
        module Answering
          # The tag #pass throws to its #dispatch_key.
          PASS = :bbs_pages_pass

          # Leaves the key being answered to the next binding of the key map
          # (and, when none takes it, to whatever comes after it). Call it only
          # inside a #key block.
          def pass = throw(PASS)

          # Runs the first binding of the class's key map that matches +key+
          # and does not #pass. Returns the Keymap::Binding that took the key,
          # +nil+ when none did.
          def dispatch_key(key)
            self.class.keymap.each do |binding|
              next unless binding.match?(key)

              taken = false
              catch(PASS) do
                instance_exec(key, &binding.action)
                taken = true
              end
              return binding if taken
            end
            nil
          end
        end
      end
    end
  end
end
