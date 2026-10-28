# frozen_string_literal: true

module BBS
  # Base widget. All visual elements inherit from this.
  #
  # [bounds] a Rect (x, y, width, height) in screen coordinates
  # [parent] the enclosing Container, or +nil+
  # [id]     an optional Symbol for lookup via Container#find
  #
  # Subclasses override #render and optionally #handle_event.
  class Widget
    # A rectangle of screen cells: +x+ and +y+ are the 1-based top-left cell,
    # +width+ and +height+ the size. <tt>contains?(px, py)</tt> tells whether
    # a cell lies inside it.
    Rect = Struct.new(:x, :y, :width, :height) do
      def contains?(px, py)
        px >= x && px < x + width && py >= y && py < y + height
      end

      def to_s = "##{x},#{y} #{width}x#{height}"
    end

    # The Rect the widget occupies, its parent Container, its lookup id, and
    # whether it is visible, has the focus, and is enabled. A new widget is
    # visible, enabled and not focused.
    attr_accessor :bounds, :parent, :id, :visible, :focused, :enabled
    # The BBS::Theme set on this widget, or +nil+ to use the parent's.
    attr_reader   :theme

    # Creates a widget.
    #
    # [id]     an optional Symbol for Container#find
    # [bounds] a Rect; defaults to an empty one at 1, 1
    # [theme]  a BBS::Theme; defaults to the parent's
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

    # Returns the SGR style for +key+ from this widget's theme, or from the
    # parent's when none is set; +nil+ when neither has a theme.
    def style(key)
      th = @theme || (parent && parent.theme)
      th ? th.style(key) : nil
    end
  end
end
