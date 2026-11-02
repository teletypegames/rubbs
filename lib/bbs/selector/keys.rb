# frozen_string_literal: true

module BBS
  class Selector
    # How a Selector reads the caller's keys: what a key takes (#take),
    # and how the others move the light (#react).
    module Keys
      private

      # What +key+ takes, as a one-element Array (the value may be +nil+), or
      # +nil+ when it takes nothing.
      def take(key)
        return [@back] if BACK_KEYS.include?(key)
        return [@items[@index].value] if key == :enter
        return [@exits[fold(key)]] if @exits.key?(fold(key))
        return [[@item_exits[fold(key)], @items[@index].value]] if @item_exits.key?(fold(key))

        item = hotkey(key)
        return unless item

        light(@items.index(item))
        [item.value]
      end

      def hotkey(key)
        return unless letter?(key)

        @items.find { |i| i.selectable? && i.key.to_s.downcase == key.downcase }
      end

      # Whether +key+ is a single character that can be an item's key: not a
      # digit of +numbers+.
      def letter?(key) = key.is_a?(String) && key.length == 1 && !(@numbers && key.match?(DIGIT))

      def react(key)
        case key
        when *STEP_KEYS.keys then move(STEP_KEYS[key])
        when *SIDE_KEYS.keys then @layout.side(self, SIDE_KEYS[key])
        when *PAGE_KEYS.keys then turn(PAGE_KEYS[key])
        when :home then light(step(-1, 1))
        when :end then light(step(@items.size, -1))
        else typing(key)
        end
      end

      # Backspace and the digits of a number being typed.
      def typing(key)
        if key == :backspace then type(@typed.chop)
        elsif @numbers && key.is_a?(String) && key.match?(DIGIT) then type(@typed + key)
        end
      end

      # The digits typed so far as +digits+: the item of that number lit when
      # there is one; a digit that would make no item's number is dropped.
      def type(digits)
        return if digits.length > MAX_DIGITS
        return if !digits.empty? && !digits.to_i.between?(1, @items.size)

        @typed = digits
        @typed.empty? ? repaint([rows]) : light(@typed.to_i - 1)
      end
    end

    include Keys
  end
end
