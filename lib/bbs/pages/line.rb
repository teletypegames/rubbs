# frozen_string_literal: true

module BBS
  class Pages
    # The line of text BBS::Pages#read_line is reading: what the caller
    # typed so far, and what the screen shows around it. The runner keeps
    # it while the line is read (BBS::Pages#line) and the page or the
    # runner draws it, in its own look, where it wants.
    #
    # Keys: a printable character is added (up to +max+), DEL or backspace
    # takes the last one back, RETURN takes the line, RUN/STOP, Esc or
    # Ctrl-C gives it up.
    class Line
      # The keys that give the line up.
      CANCEL_KEYS = %i[escape interrupt].freeze

      # [label] the words before the line (+nil+ for none)
      # [hint]  a line of help to show with it (+nil+ for none)
      # [max]   the most characters it takes, +nil+ for no limit
      attr_reader :label, :hint, :max
      # The text typed so far.
      attr_reader :text

      # A line starting from +text+; see the attributes.
      def initialize(label: nil, hint: nil, text: '', max: nil)
        @label = label
        @hint  = hint
        @max   = max
        @text  = +text.to_s
        @text  = @text[0, max] if max
      end

      # Answers +key+. Returns +:done+ on RETURN, +:cancel+ on a cancel
      # key, +nil+ otherwise (the text may have changed).
      def key(key)
        case key
        when :enter then :done
        when *CANCEL_KEYS then :cancel
        when :backspace then @text.chop! && nil
        when String then add(key)
        end
      end

      # The last +width+ characters of the text: the part a field of that
      # width shows, the end in sight.
      def tail(width) = @text[-[width, 1].max..] || @text

      private

      def add(key)
        @text << key if Text.printable?(key) && (@max.nil? || @text.length < @max)
        nil
      end
    end
  end
end
