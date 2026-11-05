# frozen_string_literal: true

require 'forwardable'
require_relative 'screen'
require_relative '../common/screens/paint'
require_relative 'face/sayings'
require_relative '../common/auth/conveniences'

module Rubbs
  module Petscii
    # The line-by-line face of a board (a Commodore 64's 40×25, or a modern
    # terminal line by line), declared in a subclass: its title bar, its
    # masthead and its main menu; its own methods say what each item does.
    #
    #   class UI::Petscii < Rubbs::Petscii::Face
    #     title('ALEXANDRIA BBS') { "#{lang}.wikipedia" }
    #
    #     masthead do
    #       art  PHAROS
    #       logo 'ALEXANDRIA', colors: LOGO_COLORS
    #       line 'wikipedia on your commodore', color: WH
    #     end
    #
    #     main_menu do
    #       item 'r', 'random article', 'wherever the wiki takes you' do random end
    #       item('l', -> { "language: #{language}" }, 'the next wikipedia') { next_language }
    #       log_off 'hang up. see you!'
    #     end
    #   end
    #
    # Rubbs.board (or a Flow's +face+ step) makes one per call with the
    # session, the context and the board's domain object, whose services
    # are readers of the face, and calls #run: the masthead, then the main
    # menu until the caller logs off. A subclass overrides #run for any
    # other shape, using #home, #main_menu_choice and the screen's helpers,
    # which the face answers itself (#puts, #say, #title, #pick, #page,
    # #alert, #prompt, #each_pick, #within, #qr, #markdown …).
    #
    # The C64 colours (Rubbs::Petscii::Colors), +COLS+ and +WIDTH+ are
    # constants of every subclass, so classes nested in it see them too.
    class Face
      extend Forwardable
      include Colors
      include Common::Screens::Paint
      include Sayings
      include Common::Auth::Conveniences

      # The colours of the roles of Rubbs::Common::Screens::Paint on a C64.
      ROLES = { text: LG, text_dim: GR, text_bright: WH, accent: YE, label: CY, error: RD, success: GN }.freeze

      # The hint under a main menu.
      MENU_HINT = 'crsr: choose  return: take'

      # The screen's width in columns.
      COLS = Screen::COLS
      # The width of text on it, a column from each side.
      WIDTH = Screen::WIDTH

      # Copies the colours, COLS and WIDTH into +subclass+.
      def self.inherited(subclass)
        super
        Colors.install(subclass)
        subclass.const_set(:COLS, COLS) unless subclass.const_defined?(:COLS, false)
        subclass.const_set(:WIDTH, WIDTH) unless subclass.const_defined?(:WIDTH, false)
      end

      class << self
        # The home title bar: +text+, and the block's text (evaluated in the
        # face) at its right end. Without arguments returns
        # <tt>[text, block]</tt>.
        def title(text = nil, &right)
          return @title || superclass_value(:title) if text.nil?

          @title = [text, right]
        end

        # Declares the masthead the call starts with, evaluated in a
        # Masthead.
        def masthead(&block)
          return @masthead || superclass_value(:masthead) unless block

          @masthead = Masthead.new(&block)
        end

        # Declares the main menu, evaluated in a MainMenu: +item+, +heading+,
        # +each_of+, +log_off+. +hint+ is its hint row (default MENU_HINT),
        # +back+ the key of the item ← (RUN/STOP) takes (default the log-off
        # item), +home+ what each round draws above it (+:title+ or
        # +:masthead+), +above+ a block of lines above the menu, +gap+ where
        # the empty line goes (+:before+ those lines, +:after+, or +false+).
        def main_menu(hint: MENU_HINT, back: nil, home: :title, above: nil, gap: :before, &block)
          return @main_menu || superclass_value(:main_menu) unless block

          @main_menu = MainMenu.new(hint, back, home: home, above: above, gap: gap, &block)
        end

        # Declares the sub-menu +name+, a MainMenu under a title of its own
        # (+title+, and +right+: a String or a block evaluated in the face),
        # its items declared like the main menu's, +back+ (the item) leaving
        # it. Face#sub_menu runs it. +above+ and +gap+ are those of #main_menu.
        #
        #   sub_menu(:jargon, title: 'THE JARGON FILE', right: '4.4.7') do
        #     item('1', 'word of the day', 'the same for everyone today') { word_of_the_day }
        #     back 'to the main menu'
        #   end
        def sub_menu(name, title:, right: '', hint: MENU_HINT, above: nil, gap: :before, &)
          sub_menus[name] = MainMenu.new(hint, nil, home: [title, right], above: above, gap: gap, &)
        end

        # The declared sub-menus by name, the superclass's too.
        def sub_menus
          @sub_menus ||= superclass.respond_to?(:sub_menus) ? superclass.sub_menus.dup : {}
        end

        private

        def superclass_value(name) = superclass.respond_to?(name) ? superclass.public_send(name) : nil
      end

      def_delegators :@screen,
                     :puts,
                     :say,
                     :write,
                     :cls,
                     :bell,
                     :title_bar,
                     :rule,
                     :rule_line,
                     :wrap,
                     :fit,
                     :plain,
                     :key,
                     :page,
                     :pick,
                     :ask,
                     :edit,
                     :pause,
                     :choose,
                     :actions,
                     :menu,
                     :within,
                     :alert,
                     :notice,
                     :prompt,
                     :confirm?,
                     :number,
                     :each_pick,
                     :markdown,
                     :qr,
                     :page_size

      # The Rubbs::Petscii::Screen, the session, the call's context and the
      # board's domain object.
      attr_reader :screen, :session, :context, :board

      # The key of the item taken last from each menu (MainMenu => key),
      # where the menu's cursor starts.
      def cursors = @cursors ||= {}

      # The key of the main menu's item taken last.
      def menu_cursor = cursors[self.class.main_menu]

      # Whether the masthead is on the screen and the main menu goes under it
      # (set by #show_masthead, cleared by the menu).
      attr_writer :masthead_up

      # See #masthead_up=.
      def masthead_up? = @masthead_up == true

      # A face for one call on +session+, with the +context+ of the call and
      # the +board+ (its services become readers).
      def initialize(session, context = {}, board = nil)
        @session = session
        @context = context
        @board   = board
        @screen  = make_screen(session)
        define_service_readers
      end

      # The call: the masthead, then the main menu until the caller logs
      # off.
      def run
        show_masthead
        main_menu_loop
      end

      # Draws a title bar on a cleared screen; without arguments, the home
      # one (Face.title).
      def title(text = nil, right = '')
        return @screen.title(text, right) if text

        home
      end

      # Draws the home title bar (Face.title).
      def home
        text, right = self.class.title
        @screen.title(text.to_s, right ? instance_exec(&right).to_s : '')
      end

      # Writes the masthead (Face.masthead) on a cleared screen; the main
      # menu goes under it.
      def show_masthead
        cls
        self.class.masthead&.draw(self)
        @masthead_up = true
      end

      # The screen of the call on +session+: a Rubbs::Petscii::Screen. A face
      # overrides it for a screen of its own class or size.
      def make_screen(session) = Screen.new(session)

      # Shows the main menu (Face.main_menu) under what is on the screen and
      # runs the taken item. Returns +:log_off+ when the caller logs off.
      def main_menu_choice
        self.class.main_menu.take(self)
      end

      # Runs the main menu again and again until the caller logs off; a
      # Rubbs::Common::Line::Abort from an item (#fail_with) leaves the caller at the menu.
      def main_menu_loop
        loop do
          break if main_menu_choice == :log_off
        rescue Common::Line::Abort
          next
        end
      end

      private

      def paint_style(role) = ROLES.fetch(role, LG)

      def paint_reset = LG

      def define_service_readers
        return unless @board.respond_to?(:services)

        @board.services.each do |name, service|
          define_singleton_method(name) { service } unless respond_to?(name, true)
        end
      end
    end
  end
end

require_relative 'face/masthead'
require_relative 'face/main_menu'
