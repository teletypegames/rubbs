# frozen_string_literal: true

require_relative '../line/hangup'
require_relative 'pages/keymap'
require_relative 'pages/printing'

module Rubbs
  module Common
    module Screens
      # A full-screen "page app" for both faces: a stack of Rubbs::Common::Screens::Page objects,
      # the top one on the screen. The runner reads the keys, gives each to the
      # page (and to its own key map after), repaints after it by sending only
      # the cells that changed, and runs the timers of #every while the caller
      # is silent.
      #
      # On a modern terminal a page draws into a Rubbs::Modern::FrameBuffer the size of
      # the terminal and the runner writes its Rubbs::Modern::FrameBuffer#diff; on a C64
      # (a session in PETSCII mode, or <tt>face: :petscii</tt>) it draws into a
      # Rubbs::Petscii::Canvas in +charset+ and the runner writes its
      # Rubbs::Petscii::Canvas#diff raw.
      #
      # Navigation is by name: #push, #back, #replace, #reset, #quit. A page
      # waits for an answer with #show, reads a line with #read_line and gives
      # the line to someone else (a gateway, a banner) with #hand_over. A
      # hang-up raises Rubbs::Common::Line::Hangup out of #run.
      #
      # A subclass is the app around the pages: it can draw a frame around
      # them (#draw), take keys before the page (#handle), declare keys of its
      # own for the ones no page takes and timers (Rubbs::Common::Screens::Pages::Keymap):
      #
      #   class Gate < Rubbs::Common::Screens::Pages
      #     key('q') { quit }
      #     every(0.5) { redraw }
      #
      #     def draw(canvas)
      #       canvas.text(0, 1, Time.now.strftime('%H:%M'), :grey)
      #       super
      #     end
      #   end
      #
      #   Gate.new(session, charset: :lower).run(Home.new)
      class Pages
        extend Keymap
        include Answering
        include Printing

        # The tag #quit throws to #run and #press.
        QUIT = :bbs_pages_quit
        # The faces a runner draws for.
        FACES = %i[modern petscii].freeze
        # What a modern terminal gets before the first screen and after a
        # #hand_over: the colours reset, the screen cleared, the cursor home.
        MODERN_CLEAR = "#{Modern::Ansi::RESET}#{Modern::Ansi::CLEAR}".freeze
        # What a modern terminal gets when the line comes back from a
        # #hand_over: the colours reset, mouse reporting off, the cursor shown.
        MODERN_RESTORE = "#{Modern::Ansi::RESET}#{Common::Line::Telnet::Mouse::MOUSE_OFF}#{Modern::Ansi::SHOW_CURSOR}".freeze

        # The session the runner reads and writes.
        attr_reader :session
        # The face it draws for: +:modern+ or +:petscii+.
        attr_reader :face
        # The character set of the C64 face (Rubbs::Petscii::Canvas#charset).
        attr_reader :charset
        # The pages, the one on the screen last. Change it with the navigation
        # methods, not directly.
        attr_reader :stack
        # The Rubbs::Common::Screens::Pages::Line #read_line is reading, +nil+ when none.
        attr_reader :line
        # The value #quit was given, once the runner is #done?.
        attr_reader :result

        # A runner on +session+.
        #
        # [face]    +:modern+ or +:petscii+; default +:petscii+ when the session
        #           is in PETSCII mode
        # [charset] the Rubbs::Petscii::Canvas character set of the C64 face,
        #           +:upper+ or +:lower+
        #
        # Raises ArgumentError for another face.
        def initialize(session, face: nil, charset: :upper)
          @session = session
          @face    = face || (session.respond_to?(:petscii?) && session.petscii? ? :petscii : :modern)
          raise ArgumentError, "not a face: #{@face.inspect}" unless FACES.include?(@face)

          @charset = charset
          @stack   = []
          @done    = false
          @fired   = {}
        end

        # Whether the runner draws for a C64.
        def petscii? = @face == :petscii

        # The page on the screen, +nil+ before #start.
        def page = @stack.last

        # Runs the pages from +page+ (or from the stack as it is when +nil+)
        # until #quit or the caller is silent past the session's
        # +idle_seconds+ (only counted while a timer of #every polls). What
        # Rubbs::Common::Line::Session#announce tells the caller meanwhile is
        # shown after the next key, a Rubbs::Common::Screens::Notice each.
        # Returns the value given to #quit, +nil+ for an idle end. Raises
        # Rubbs::Common::Line::Hangup when the caller hangs up.
        def run(page = nil)
          outer = listen_announcements
          catch(QUIT) do
            start(page) if page
            loop do
              press!(wait_key)
              show_announcements
            end
          end
          @result
        ensure
          @session.on_announce(outer) if @announcements
        end

        # Shows each notice waiting (#run), a Rubbs::Common::Screens::Notice
        # until a key. Returns +nil+.
        def show_announcements
          show(Notice.new(@announcements.pop)) while @announcements && !@announcements.empty? && !@done
          nil
        end

        # Puts +page+ alone on the stack and paints the whole screen; the first
        # step of #run, public for a test that presses keys one by one (#press).
        # Returns the bytes written.
        def start(page)
          @stack.clear
          put(page)
          redraw(whole: true)
        end

        # Answers +key+ (#handle) and repaints, as #run does for each key.
        # Returns whether the runner is #done? after it.
        def press(key)
          catch(QUIT) { press!(key) }
          @done
        end

        # Whether #quit ended the runner.
        def done? = @done

        # Answers +key+: the page first (Rubbs::Common::Screens::Page#handle), then the runner's
        # own key map. Override it to take keys before the page. Returns the
        # binding that took it (truthy), +nil+ when none did.
        def handle(key) = page&.handle(key) || dispatch_key(key)

        # Draws the screen on +screen+ (see Rubbs::Common::Screens::Page#draw): the page on top.
        # Override it to draw a frame around the page, calling +super+.
        def draw(screen) = page&.draw(screen)

        # Puts +page+ on top of the stack and calls its Rubbs::Common::Screens::Page#enter.
        # Returns +page+.
        def push(page) = put(page)

        # Takes the page on top off the stack and calls Rubbs::Common::Screens::Page#resume of
        # the one under it; with a single page on the stack, #quit. Override
        # it for another way back (a home page).
        def back
          return quit if @stack.size <= 1

          @stack.pop
          page.resume
          page
        end

        # Puts +page+ in place of the one on top (Rubbs::Common::Screens::Page#enter). Returns
        # +page+.
        def replace(page)
          @stack.pop
          put(page)
        end

        # Puts +page+ alone on the stack (Rubbs::Common::Screens::Page#enter). Returns +page+.
        def reset(page)
          @stack.clear
          put(page)
        end

        # Ends the runner: #run returns +value+, #press returns +true+. Does
        # not return (it throws to #run).
        def quit(value = nil)
          @done   = true
          @result = value
          throw QUIT
        end

        private

        def listen_announcements
          return unless @session.respond_to?(:on_announce)

          outer = @session.respond_to?(:announcer) ? @session.announcer : nil
          @announcements = Thread::Queue.new
          @session.on_announce(->(text) { @announcements << text })
          outer
        end

        def press!(key)
          handle(key)
          redraw
        end

        def put(page)
          page.pages = self
          @stack.push(page)
          page.enter
          page
        end
      end
    end
  end
end

require_relative 'pages/line'
require_relative 'pages/painting'
require_relative 'pages/waiting'
