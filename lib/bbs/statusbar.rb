# frozen_string_literal: true

require_relative 'widget'

module BBS
  # A status bar at the bottom of the screen. Render a list of hotkey hints
  # like "F1=Help F2=Save Esc=Cancel". Optionally a right-aligned status text.
  # While a #message is set, the bar shows it in place of the hints: the
  # Application sets the hint of the highlighted menu entry there.
  class Statusbar < Widget
    # A function key label, <tt>F1</tt> ... <tt>F12</tt>; the group is the
    # number.
    FKEY_LABEL = /\AF(\d+)\z/i
    # An Alt key label, <tt>Alt-X</tt>; the group is the letter.
    ALT_LABEL  = /\AAlt-(.)\z/i
    # The Escape key label.
    ESC_LABEL  = /\AEsc\z/i
    # The Tab key label.
    TAB_LABEL  = /\ATab\z/i

    # One hint: the key as shown (+F1+, <tt>Alt-x</tt>, +Esc+, +Tab+ or a
    # literal key), its label, the block run when it is activated, and
    # whether it is hidden.
    Hint = Struct.new(:key, :label, :on_activate, :hidden, keyword_init: true)

    # The Array of Hint objects, and the text shown at the right end (or
    # +nil+).
    attr_accessor :hints, :right_text
    # A line shown in place of the hints while it is set (+nil+ shows the
    # hints).
    attr_accessor :message

    # Creates a status bar with +hints+ (an Array of Hint) and an optional
    # +right_text+. Other keywords go to Widget.new.
    def initialize(hints: [], right_text: nil, **kw)
      super(**kw)
      @hints      = hints
      @right_text = right_text
      @message    = nil
    end

    # Adds a hint for +key+ with +label+; the block runs when the key is
    # pressed or the hint is clicked. A hidden hint is a key binding only:
    # it works, but takes no room.
    def add_hint(key, label, hidden: false, &on_activate)
      @hints << Hint.new(key: key, label: label, on_activate: on_activate, hidden: hidden)
    end

    # Returns the hints that are not hidden.
    def shown = @hints.reject(&:hidden)

    # Draws the bar across its bounds in +frame+: the #message across the
    # whole bar, or else the shown hints from the left, as many as fit, and
    # the right text when there is room for it.
    def render(frame)
      frame.move(bounds.x, bounds.y)
      frame.write(' ' * bounds.width, sgr: style(:statusbar))
      return render_message(frame) if @message

      placed.each { |hint, x| render_hint(frame, hint, x) }
      render_right_text(frame)
    end

    # Runs the hint whose key matches a key +event+, or the shown hint under
    # a left click on the bar.
    #
    # Returns the hint block's result, or +:handled+ when it returns +nil+;
    # +nil+ when no hint matches.
    def handle_event(event)
      hint = event.key? ? match_key(event.key) : clicked(event)
      hint && (hint.on_activate&.call || :handled)
    end

    private

    # The text of +hint+ on the bar: its key, then its label between spaces.
    def hint_text(hint) = [hint.key.to_s, " #{hint.label} "]

    def hint_width(hint) = hint_text(hint).sum(&:length)

    # The shown hints that fit, each with the column it starts at.
    def placed
      x = bounds.x + 1
      shown.each_with_object([]) do |hint, list|
        break list if x + hint_width(hint) > bounds.x + bounds.width - 1

        list << [hint, x]
        x += hint_width(hint) + 1
      end
    end

    def render_message(frame)
      frame.move(bounds.x + 1, bounds.y)
      frame.write('▸ ', sgr: style(:statusbar_key))
      frame.write(FrameBuffer.clip_ansi(@message.to_s, [bounds.width - 4, 0].max), sgr: style(:statusbar))
    end

    def render_hint(frame, hint, x)
      key, label = hint_text(hint)
      frame.move(x, bounds.y)
      frame.write(key, sgr: style(:statusbar_key))
      frame.write(label, sgr: style(:statusbar))
    end

    # The right text, when it fits right of the hints.
    def render_right_text(frame)
      return unless @right_text

      text = @right_text.to_s
      x    = bounds.x + bounds.width - text.length - 1
      return if x < hints_end

      frame.move(x, bounds.y)
      frame.write(text, sgr: style(:statusbar))
    end

    # The first free column right of the placed hints.
    def hints_end
      hint, x = placed.last
      hint ? x + hint_width(hint) + 1 : bounds.x + 1
    end

    # The shown hint under a left click +event+ on the bar, or +nil+.
    def clicked(event)
      return nil unless event.click? && event.y == bounds.y

      placed.find { |hint, x| event.x >= x && event.x < x + hint_width(hint) }&.first
    end

    def match_key(key)
      key_str = key.to_s
      @hints.find do |hint|
        label = hint.key.to_s
        case label
        when FKEY_LABEL then key == :"f#{::Regexp.last_match(1)}"
        when ALT_LABEL  then key == :"alt_#{::Regexp.last_match(1).downcase}"
        when ESC_LABEL  then key == :escape
        when TAB_LABEL  then key == :tab
        else                 key_str.casecmp?(label)
        end
      end
    end
  end
end
