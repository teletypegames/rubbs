# frozen_string_literal: true

module BBS
  # A normalised event delivered to widgets.
  #
  #   kind  — :key, :mouse, :idle, :resize, :tick
  #   key   — Symbol (:up, :enter, :f1, …) or single-char String (for :key)
  #   mouse — Telnet::MouseEvent (for :mouse)
  #   x, y  — terminal-relative cursor position (for :mouse)
  Event = Struct.new(:kind, :key, :mouse, :x, :y, keyword_init: true) do
    def self.key(name)
      new(kind: :key, key: name)
    end

    def self.mouse(mevt)
      new(kind: :mouse, mouse: mevt, x: mevt.x, y: mevt.y)
    end

    def self.idle  = new(kind: :idle)
    def self.tick  = new(kind: :tick)
    def self.resize(cols, rows) = new(kind: :resize, x: cols, y: rows)

    def key? = kind == :key
    def mouse? = kind == :mouse
    def alt? = key? && key.to_s.start_with?('alt_')
    def alt_char = alt? ? key.to_s.sub('alt_', '') : nil
    def char? = key? && key.is_a?(String) && key.length == 1
  end
end
