# frozen_string_literal: true

module BBS
  module Kit
    module Modern
      # The runner of a board's tabs on a modern terminal: one page a tab
      # (+sides+), each keeping its place while another is shown, in the
      # order of the Look's tabs; #switch goes round them. A tab of
      # +actions+ runs its callable instead (given the runner: a profile
      # that takes the screen), and the caller comes back to the tab they
      # left. The line read (BBS::Pages#read_line) is drawn at the bottom
      # (Prompt).
      #
      #   tabs = BBS::Kit::Modern::Tabs.new(session, look: look, sides: { own: own, discovery: home },
      #                                     actions: { profile: ->(t) { t.hand_over { Profile.run(session) } } })
      #   tabs.run
      class Tabs < BBS::Pages
        include Style
        include Prompt

        # The Look.
        attr_reader :look
        # The tab shown.
        attr_reader :side

        # Tabs for the caller on +session+ in +look+: +sides+ (key => the
        # tab's page) and +actions+ (key => a callable given the runner),
        # starting on +start+ (the first side by default).
        def initialize(session, look:, sides:, actions: {}, start: nil)
          super(session, face: :modern)
          @look    = look
          @sides   = sides
          @actions = actions
          @side    = start || sides.keys.first
        end

        # Runs from the tab shown (or on from where it was) until the caller
        # leaves.
        def run(page = (@sides[@side] if stack.empty?)) = super

        # Turns to the next tab (+step+ 1) or the one before (-1).
        def switch(step = 1)
          order = @look.tabs.keys
          open_tab(order[((order.index(@side) || 0) + step) % order.size])
        end

        # Opens the tab +key+: an action runs and the tab shown comes back; a
        # side is shown from its page.
        def open_tab(key)
          if @actions.key?(key)
            @actions[key].call(self)
          elsif @sides.key?(key)
            @side = key
          end
          reset(@sides[@side])
        end

        # Draws the page and the line being read.
        def draw(frame)
          super
          prompt(frame) if line
        end
      end
    end
  end
end
