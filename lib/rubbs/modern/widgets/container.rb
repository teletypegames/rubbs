# frozen_string_literal: true

module Rubbs
  module Modern
    module Widgets
      # A Widget that holds children. It renders them in order, so a later child
      # draws over an earlier one, and passes hit tests and themes down to them.
      class Container < Widget
        # The child widgets as an Array, in drawing order.
        attr_reader :children

        # Creates an empty container. Takes the same keywords as Widget.new.
        def initialize(**kw)
          super
          @children = []
        end

        # Appends +child+ and makes this container its parent.
        #
        # Returns +child+.
        def add(child)
          child.parent = self
          @children << child
          child
        end

        # Removes +child+ and clears its parent. Does nothing when +child+ is not
        # one of the children.
        def remove(child)
          child.parent = nil if @children.delete(child)
        end

        # Removes all children and clears their parent.
        def clear
          @children.each { |c| c.parent = nil }
          @children.clear
        end

        # Returns an Array of the visible widgets in the tree (this container and
        # every level below) that accept focus, in walk order.
        def focusable_descendants
          result = []
          walk { |w| result << w if w.focusable? && w.visible }
          result
        end

        # Yields this container, then every widget below it, depth first in
        # child order. Nested containers are walked in turn.
        def walk(&block)
          yield self
          @children.each do |c|
            c.is_a?(Container) ? c.walk(&block) : (yield c)
          end
        end

        # Returns the first widget in the tree whose +id+ equals +id+, or +nil+.
        def find(id)
          walk { |w| return w if w.id == id }
          nil
        end

        # Renders the visible children into +frame+, a Rubbs::Modern::FrameBuffer, in
        # order.
        def render(frame)
          @children.each { |c| c.render(frame) if c.visible }
        end

        # Returns the top-most visible widget under the screen cell (+x+, +y+):
        # the deepest child hit, this container when no child is hit, or +nil+
        # when the point is outside the bounds or the container is hidden.
        def hit_test(x, y)
          return nil unless bounds.contains?(x, y) && visible

          # iterate top-most last so we test in reverse
          @children.reverse.each do |child|
            next unless child.visible

            hit = child.hit_test(x, y)
            return hit if hit
          end
          self
        end

        # Sets the Rubbs::Modern::Theme on this container and on every child.
        def theme=(value)
          super
          @children.each { |c| c.theme = value }
        end
      end
    end
  end
end
