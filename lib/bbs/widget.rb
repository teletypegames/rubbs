# frozen_string_literal: true

module BBS
  # Base widget. All visual elements inherit from this.
  #
  #   bounds — Rect (x, y, width, height) in screen coordinates
  #   parent — enclosing Container, or nil
  #   id     — optional symbol for lookup via Container#find
  #
  # Subclasses override render(frame) and optionally handle_event(event).
  class Widget
    Rect = Struct.new(:x, :y, :width, :height) do
      def contains?(px, py)
        px >= x && px < x + width && py >= y && py < y + height
      end

      def to_s = "##{x},#{y} #{width}x#{height}"
    end

    attr_accessor :bounds, :parent, :id, :visible, :focused, :enabled
    attr_reader   :theme

    def initialize(id: nil, bounds: nil, theme: nil)
      @id       = id
      @bounds   = bounds || Rect.new(1, 1, 0, 0)
      @parent   = nil
      @visible  = true
      @focused  = false
      @enabled  = true
      @theme    = theme
    end

    # Override in subclasses. By default a widget does not accept focus.
    def focusable? = false

    # Called when this widget gains focus. Subclasses may override.
    def on_focus = nil

    # Called when this widget loses focus.
    def on_blur = nil

    # Render this widget into the supplied FrameBuffer.
    def render(frame); end

    # Handle a keyboard or mouse event. Return :halt to end the application,
    # :handled to stop propagation, or nil/false to continue.
    def handle_event(_event) = nil

    # Convenience: yield this widget. Subclasses override to walk a tree.
    def each(&block)
      yield self
      nil
    end

    # Hit test: returns the deepest widget whose bounds contain (x, y).
    def hit_test(x, y)
      bounds.contains?(x, y) ? self : nil
    end

    # Apply a theme. Subclasses with children propagate via Container#theme=.
    def theme=(value)
      @theme = value
    end

    # Move/resize. Subclasses may override to relayout children.
    def layout(x, y, width, height)
      @bounds = Rect.new(x, y, width, height)
    end

    # Request a redraw — set by Application as a callback if needed.
    def redraw!
      @parent&.redraw!
    end

    protected

    def style(key)
      th = @theme || (parent && parent.theme)
      th ? th.style(key) : nil
    end
  end
end
