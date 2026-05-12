# frozen_string_literal: true

module BBS
  # A Widget that holds children.
  class Container < Widget
    attr_reader :children

    def initialize(**kw)
      super
      @children = []
    end

    def add(child)
      child.parent = self
      @children << child
      child
    end

    def remove(child)
      child.parent = nil if @children.delete(child)
    end

    def clear
      @children.each { |c| c.parent = nil }
      @children.clear
    end

    def focusable_descendants
      result = []
      walk { |w| result << w if w.focusable? && w.visible }
      result
    end

    def walk(&block)
      yield self
      @children.each do |c|
        c.is_a?(Container) ? c.walk(&block) : (yield c)
      end
    end

    def find(id)
      walk { |w| return w if w.id == id }
      nil
    end

    def render(frame)
      @children.each { |c| c.render(frame) if c.visible }
    end

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

    def theme=(value)
      super
      @children.each { |c| c.theme = value }
    end
  end
end
