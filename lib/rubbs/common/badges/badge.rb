# frozen_string_literal: true

module Rubbs
  module Common
    module Badges
      # A badge of the network: its +key+ (a String), the +board+ whose file
      # declares it, what it is called (+title+), what to do for it
      # (+hint+), its +emblem+ (one character) and +color+ (a Symbol of
      # COLORS), whether it is +secret+ (shown as <tt>???</tt> until earned)
      # or +manual+ (given by a sysop, no rule), and either a +rule+ (a Rule)
      # or the badges it is made of (+parts+, Strings, with +needed+ of them).
      #
      # Made by Rubbs.badges (a Set), in a block:
      #
      #   badge :tourist do
      #     title  'Tourist'
      #     hint   'Call five different boards of the network.'
      #     emblem '♦', :cyan
      #     on(:call).distinct(:board).reaches 5
      #   end
      class Badge
        # The colours an emblem can have, the same names on both faces.
        COLORS = %i[white red green blue yellow cyan purple orange brown grey lightblue lightgreen lightred].freeze
        # The colour of each tier name a Rule commonly uses.
        TIER_COLORS = { 'bronze' => :orange, 'silver' => :grey, 'gold' => :yellow }.freeze

        # See the class comment.
        attr_reader :key, :board, :rule, :parts, :needed

        # A badge +key+ of +board+, made by the block (evaluated in the badge,
        # see the class comment); +secret+ and +manual+ as the class comment
        # says.
        def initialize(key, board:, secret: false, manual: false, &block)
          @key    = key.to_s
          @board  = board.to_s
          @secret = secret
          @manual = manual
          @parts  = []
          @needed = 0
          @color  = :white
          instance_eval(&block) if block
        end

        # Sets the title, or without +text+ returns it (the key's words when
        # none was set).
        def title(text = nil) = text ? (@title = text.to_s) : (@title || @key.tr('_', ' ').capitalize)

        # Sets what to do for the badge, or without +text+ returns it.
        def hint(text = nil) = text ? (@hint = text.to_s) : @hint.to_s

        # Sets the emblem (one character) and its +color+, or without +char+
        # returns the character.
        def emblem(char = nil, color = nil)
          return @emblem if char.nil?

          @emblem = char.to_s
          @color = color if color
          @emblem
        end

        # The emblem's colour.
        attr_reader :color

        # Whether it is shown only once earned.
        def secret? = @secret

        # Whether a sysop gives it, not a rule.
        def manual? = @manual

        # Whether it is made of other badges (#all_of, #any_of).
        def composite? = !@parts.empty?

        # The events it counts: the rule on the events named +event+ whose
        # fields match +filter+ (see Rule#new); its measure and goal follow by
        # chaining. On a board's badge the board is the board's own unless the
        # filter names one (<tt>board: :any</tt> for every board).
        def on(event, **filter)
          filter = filter.merge(board: @board) unless filter.key?(:board) || @board == NETWORK
          filter.delete(:board) if filter[:board] == :any
          @rule = Rule.new(event, filter)
        end

        # Earned with every one of the badges +keys+.
        def all_of(*keys) = compose(keys, keys.size)

        # Earned with +count+ of the badges +keys+.
        def any_of(count, *keys) = compose(keys, count)

        # The goals as [tier, number] pairs (Rule#goals); a composite badge
        # has one, its #needed; a manual one has one of 1.
        def goals(boards)
          return [[nil, @needed]] if composite?
          return [[nil, 1]] unless @rule

          @rule.goals(boards)
        end

        # The colour of +tier+ (TIER_COLORS), else the badge's own.
        def tier_color(tier) = TIER_COLORS.fetch(tier.to_s, @color)

        # The badge as a Hash for an answer of the Central: key, title, hint,
        # emblem, color, board, secret.
        def to_h
          {
            'key'    => @key,
            'title'  => title,
            'hint'   => hint,
            'emblem' => @emblem.to_s,
            'color'  => @color.to_s,
            'board'  => @board,
            'secret' => @secret
          }
        end

        private

        def compose(keys, count)
          @parts = keys.map(&:to_s)
          @needed = count
          @rule = nil
        end
      end
    end
  end
end
