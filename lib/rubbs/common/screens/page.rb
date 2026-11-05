# frozen_string_literal: true

module Rubbs
  module Common
    module Screens
      # One full screen of a Rubbs::Common::Screens::Pages runner: it draws itself, answers its
      # keys and moves to other pages by name, not by what it returns. A page
      # draws into a Rubbs::Modern::FrameBuffer on a modern terminal and into a
      # Rubbs::Petscii::Canvas on a C64; the runner sends only what changed.
      #
      # The keys are declared on the class (see Rubbs::Common::Screens::Pages::Keymap): each block
      # runs in the page with the key. After every key the runner repaints.
      #
      #   class Board < Rubbs::Common::Screens::Page
      #     key(:enter, 'd') { hand_over { dial(board) } }
      #     key('b')         { show(Banner.new(board)) }
      #     key(:escape, 'q') { back }
      #
      #     def initialize(board) = @board = board
      #
      #     def draw(screen)
      #       print_lines(screen, [@board.name, '', 'RETURN dials   Q back'], x: 3)
      #     end
      #   end
      #
      #   Rubbs::Common::Screens::Pages.new(session).run(Board.new(board))
      #
      # Navigation (each the runner's, see Rubbs::Common::Screens::Pages): #push a page over this
      # one, #back to the one under it, #replace this one, #quit the runner;
      # #show a page until a key, #read_line, #hand_over the line, #redraw.
      # Rubbs::Common::Screens::Pages::Printing#print_lines writes lines of ANSI text.
      class Page
        extend Pages::Keymap
        include Pages::Answering
        include Pages::Printing

        # The Rubbs::Common::Screens::Pages runner showing the page; +nil+ until it is pushed.
        attr_accessor :pages

        # Draws the page on +screen+: a Rubbs::Modern::FrameBuffer (1-based cells) on a
        # modern terminal, a Rubbs::Petscii::Canvas (0-based) on a C64. The runner
        # calls it for every repaint on a fresh screen; it should only draw.
        def draw(screen); end

        # Called when the page comes on top by #push, #replace or reset (not
        # by #show); does nothing unless a subclass says otherwise.
        def enter; end

        # Called when the page is on top again after the one over it went
        # #back: the place to reload what that one may have changed.
        def resume; end

        # Answers +key+ with the page's key map (Rubbs::Common::Screens::Pages::Answering#dispatch_key).
        # Returns the binding that took it (truthy), +nil+ when none did.
        def handle(key) = dispatch_key(key)

        # The session of the runner, +nil+ before the page is pushed.
        def session = pages&.session

        # Pushes +page+ over this one (Rubbs::Common::Screens::Pages#push).
        def push(page) = pages.push(page)

        # Back to the page under this one (Rubbs::Common::Screens::Pages#back).
        def back = pages.back

        # Puts +page+ in place of this one (Rubbs::Common::Screens::Pages#replace).
        def replace(page) = pages.replace(page)

        # Ends the runner with +value+ (Rubbs::Common::Screens::Pages#quit).
        def quit(value = nil) = pages.quit(value)

        # Repaints now (Rubbs::Common::Screens::Pages#redraw).
        def redraw(whole: false) = pages.redraw(whole: whole)

        # Shows +page+ until the block answers a key (Rubbs::Common::Screens::Pages#show).
        def show(page, &) = pages.show(page, &)

        # Reads a line of text (Rubbs::Common::Screens::Pages#read_line).
        def read_line(label = nil, **, &) = pages.read_line(label, **, &)

        # Hands the line to the block (Rubbs::Common::Screens::Pages#hand_over).
        def hand_over(&) = pages.hand_over(&)
      end
    end
  end
end
