# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      # What a caller is doing now (Session#activity): +kind+ is +:section+
      # (the part of the board they opened last, Rubbs::Common::Log.use),
      # +:door+ (a Rubbs::Common::Call::Door they are inside) or +:board+
      # (a board a Rubbs::Common::Line::Gateway carries them to); +name+ says
      # which. A board counts the callers inside a door by it, not by words:
      #
      #   Rubbs.calls.count { |s| s.activity == Rubbs::Common::Line::Activity.new(:door, 'SERMO') }
      #   Rubbs.calls.map { |s| s.activity.to_s }   # => ["feeds", "door SERMO", "› Alexandria BBS"]
      Activity = Data.define(:kind, :name) do
        # A sysop's words for it: the section's name, <tt>door NAME</tt> or
        # <tt>› BOARD</tt>.
        def to_s
          case kind
          when :door then "door #{name}"
          when :board then "› #{name}"
          else name.to_s
          end
        end
      end

      # What a line keeps of what its caller is doing (an Activity, or +nil+),
      # and a way to do something for a while (Activities#doing).
      module Activities
        # What the caller is doing now: an Activity, +nil+ before anything.
        attr_accessor :activity

        # Runs the block with the activity of +kind+ and +name+, the one before
        # back afterwards however it ends. Returns the block's value.
        #
        #   session.doing(:door, 'SERMO') { sermo.run(session) }
        def doing(kind, name)
          before = activity
          self.activity = Activity.new(kind: kind, name: name.to_s)
          yield
        ensure
          self.activity = before
        end
      end
    end
  end
end
