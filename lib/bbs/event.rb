# frozen_string_literal: true

module BBS
  # A normalised event delivered to widgets.
  #
  #   kind  — :key, :mouse, :idle, :resize, :tick
  #   key   — Symbol (:up, :enter, :f1, …) or single-char String (for :key)
  #   mouse — Telnet::MouseEvent (for :mouse)
  #   x, y  — terminal-relative cursor position (for :mouse)
  #
  # For :resize, +x+ and +y+ hold the new columns and rows.
  Event = Struct.new(:kind, :key, :mouse, :x, :y, keyword_init: true) do
    # A :key event for +name+, a key Symbol or a one-character String.
    def self.key(name)
      new(kind: :key, key: name)
    end

    # A :mouse event for +mevt+, a Telnet::MouseEvent, with its position
    # copied into +x+ and +y+.
    def self.mouse(mevt)
      new(kind: :mouse, mouse: mevt, x: mevt.x, y: mevt.y)
    end

    # An :idle event: the caller has been silent for the idle time.
    def self.idle  = new(kind: :idle)
    # A :tick event: the periodic timer fired.
    def self.tick  = new(kind: :tick)
    # A :resize event for a terminal of +cols+ by +rows+ (kept in +x+ and +y+).
    def self.resize(cols, rows) = new(kind: :resize, x: cols, y: rows)

    # True for a :key event.
    def key? = kind == :key
    # True for a :mouse event.
    def mouse? = kind == :mouse
    # True for a key event whose key is an Alt combination (<tt>:alt_x</tt>).
    def alt? = key? && key.to_s.start_with?('alt_')
    # The key name after the +alt_+ prefix as a String (<tt>"x"</tt> for
    # <tt>:alt_x</tt>), or +nil+ when this is not an Alt key.
    def alt_char = alt? ? key.to_s.sub('alt_', '') : nil
    # True for a key event that is a single printable character
    # (BBS::Text.printable?: no control, no bidirectional control).
    def char? = key? && Text.printable?(key)
  end
end
