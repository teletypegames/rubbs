# frozen_string_literal: true

require_relative 'widget'

module BBS
  # A status bar at the bottom of the screen. Render a list of hotkey hints
  # like "F1=Help F2=Save Esc=Cancel". Optionally a right-aligned status text.
  class Statusbar < Widget
    # One hint: the key as shown (+F1+, <tt>Alt-x</tt>, +Esc+, +Tab+ or a
    # literal key), its label, the block run when it is activated, and
    # whether it is hidden.
    Hint = Struct.new(:key, :label, :on_activate, :hidden, keyword_init: true)

    # The Array of Hint objects, and the text shown at the right end (or
    # +nil+).
    attr_accessor :hints, :right_text

    # Creates a status bar with +hints+ (an Array of Hint) and an optional
    # +right_text+. Other keywords go to Widget.new.
    def initialize(hints: [], right_text: nil, **kw)
      super(**kw)
      @hints      = hints
      @right_text = right_text
    end

    # Adds a hint for +key+ with +label+; the block runs when the key is
    # pressed or the hint is clicked. A hidden hint is a key binding only:
    # it works, but takes no room.
    def add_hint(key, label, hidden: false, &on_activate)
      @hints << Hint.new(key: key, label: label, on_activate: on_activate, hidden: hidden)
    end

    # Returns the hints that are not hidden.
    def shown = @hints.reject(&:hidden)

    # Draws the bar across its bounds in +frame+: the shown hints from the
    # left, as many as fit, and the right text when there is room for it.
    def render(frame)
      sgr = style(:statusbar)
      key_sgr = style(:statusbar_key)
      frame.move(bounds.x, bounds.y)
      frame.write(' ' * bounds.width, sgr: sgr)

      cx = bounds.x + 1
      shown.each do |hint|
        text_key = hint.key.to_s
        text_lbl = " #{hint.label} "
        break if cx + text_key.length + text_lbl.length > bounds.x + bounds.width - 1
        frame.move(cx, bounds.y)
        frame.write(text_key, sgr: key_sgr)
        frame.write(text_lbl, sgr: sgr)
        cx += text_key.length + text_lbl.length + 1
      end

      if @right_text
        txt = @right_text.to_s
        rx  = bounds.x + bounds.width - txt.length - 1
        if rx >= cx
          frame.move(rx, bounds.y)
          frame.write(txt, sgr: sgr)
        end
      end
    end

    # Runs the hint whose key matches a key +event+, or the shown hint under
    # a left click on the bar.
    #
    # Returns the hint block's result, or +:handled+ when it returns +nil+;
    # +nil+ when no hint matches.
    def handle_event(event)
      if event.key?
        hint = match_key(event.key)
        return hint.on_activate&.call || :handled if hint
        return nil
      end

      return nil unless event.mouse? && event.mouse.kind == :press &&
                        event.mouse.button == :left && event.y == bounds.y
      cx = bounds.x + 1
      shown.each do |hint|
        text_key = hint.key.to_s
        text_lbl = " #{hint.label} "
        width    = text_key.length + text_lbl.length
        if event.x >= cx && event.x < cx + width
          return hint.on_activate&.call || :handled
        end
        cx += width + 1
      end
      nil
    end

    private

    def match_key(key)
      key_str = key.to_s
      @hints.find do |hint|
        label = hint.key.to_s
        case label
        when /\AF(\d+)\z/i  then key == :"f#{::Regexp.last_match(1)}"
        when /\AAlt-(.)\z/i then key == :"alt_#{::Regexp.last_match(1).downcase}"
        when /\AEsc\z/i     then key == :escape
        when /\ATab\z/i     then key == :tab
        else                     key_str.casecmp?(label)
        end
      end
    end
  end
end
