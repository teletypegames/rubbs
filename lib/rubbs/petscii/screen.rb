# frozen_string_literal: true

require_relative 'colors'

module Rubbs
  module Petscii
    # The screen of one call on a line-by-line board, and the ways such a
    # board talks: a reversed title bar, pages of text that wait for RETURN,
    # numbered cursor lists (Rubbs::Common::Screens::Selector), single-key and cursor menus, a
    # line field (Rubbs::Common::Screens::Field) and the full-screen editor (Rubbs::Common::Screens::Editor).
    #
    # It is made for a Commodore 64, a 40×25 screen on a session switched
    # with <tt>session.petscii!</tt>, which makes PETSCII of what the screen
    # writes. Given +cols+ and +rows+ it serves a modern terminal too: on a
    # session that is not PETSCII, #cls homes the cursor and the text is
    # not made #plain.
    #
    # The colours are the ANSI constants of Rubbs::Petscii::Colors, included,
    # so a subclass writes +WH+, +LG+ … bare. A board subclasses it for
    # methods of its own:
    #
    #   class Screen < Rubbs::Petscii::Screen
    #     def banner(text) = puts(" #{YE}#{text}#{LG}")
    #   end
    #
    #   screen = Screen.new(runner.session)
    #   screen.title('the shelves', 'q: back')
    #   book = screen.pick('the shelves', books, &:title)
    class Screen
      include Colors

      # The width of the C64 screen.
      COLS = Petscii::COLS
      # The height of the C64 screen.
      ROWS = Petscii::ROWS
      # The width of a wrapped paragraph on the C64: a column of margin on
      # both sides.
      WIDTH = COLS - 2
      # The rows above and below a page of text: the title bar, the line
      # before the key prompt, the prompt and the screen's last row.
      CHROME = 5
      # The lines of text on a C64 page (#page_size of a 40×25 screen).
      PAGE = ROWS - CHROME
      # The status row of #pick.
      PICK_HINT = 'crsr or number, return  q: back'
      # What #page and #pick show for nothing.
      EMPTY = '(nothing here)'
      # The clear screen of a modern terminal: colours reset, cursor home.
      MODERN_CLEAR = "#{Modern::Ansi::RESET}#{Modern::Ansi::CLEAR}".freeze
      # The colours of Markdown (Rubbs::Common::Text::Markdown) on this screen, in the
      # roles of a Rubbs::Modern::Theme.
      MARKDOWN = { text: LG, text_bright: WH, accent: YE, label: CY, text_dim: GR }.freeze

      # The session written to and read from (Rubbs::Common::Line::Session or one that
      # quacks like it).
      attr_reader :session
      # The screen's width and height in characters.
      attr_reader :cols, :rows
      # The width a paragraph wraps to: #cols less two.
      attr_reader :width

      # Creates the screen of +session+, +cols+ × +rows+ (default the C64's
      # 40×25).
      def initialize(session, cols: COLS, rows: ROWS)
        @session = session
        @cols    = cols
        @rows    = rows
        @width   = cols - 2
      end

      # The lines of text on a page under the title bar: #rows less CHROME.
      def page_size = @rows - CHROME

      # Whether the session speaks PETSCII; true for a session that cannot
      # tell.
      def petscii? = !@session.respond_to?(:petscii?) || @session.petscii?

      # Writes +text+ to the session as it is.
      def write(text) = @session.write(text)

      # Writes +text+ and a line end.
      def puts(text = '')
        write("#{text}\r\n")
      end

      # Clears the screen: the C64's CLR, or MODERN_CLEAR on a modern
      # terminal.
      def cls = write(petscii? ? CLEAR : MODERN_CLEAR)

      # Rings the bell.
      def bell = write("\a")

      # Clears the screen and writes the #title_bar of +text+ and +right+.
      def title(text, right = '')
        @title = [text, right]
        cls
        puts title_bar(text, right)
      end

      # The title bar's text and right end last drawn by #title, or +nil+.
      def current_title = @title

      # Runs the block under the title +text+ (and +right+), then draws the
      # title that was up before it again. Returns the block's value.
      #
      #   within("SEARCH: #{query}") { each_pick(…) { … } }
      def within(text, right = '')
        before = @title
        title(text, right)
        yield
      ensure
        title(*before) if before
      end

      # A reversed cyan bar the width of the screen less its last column:
      # +text+ (made #plain) at the left, +right+ at the right; +text+ is
      # cut where it would run into +right+.
      def title_bar(text, right = '')
        room = @cols - right.length - 1
        bar  = " #{plain(text)}".ljust(room)[0, room] + "#{right} "
        "#{CY}#{RV}#{bar}#{RO}#{LG}"
      end

      # Writes a horizontal line in +color+, the screen's width less one.
      def rule(color: DG) = puts("#{color}#{'─' * (@cols - 1)}#{LG}")

      # A rule as a line for a list of lines: +indent+ spaces, then dashes to
      # the screen's width less one.
      def rule_line(indent: 1, color: DG) = "#{' ' * indent}#{color}#{'─' * (@cols - 1 - indent)}#{LG}"

      # +text+ word-wrapped to +width+ columns, ANSI colours kept: an Array
      # of lines (Rubbs::Modern::FrameBuffer.wrap_ansi).
      def wrap(text, width = @width) = Modern::FrameBuffer.wrap_ansi(text.to_s, width)

      # +text+ in characters the C64 shows one to a cell (Rubbs::Petscii.plain)
      # on a PETSCII session; as it is on a modern one.
      def plain(text) = petscii? ? Petscii.plain(text) : text.to_s

      # Every line of +lines+ cut to +width+, the long ones wrapped under
      # their own indent. An empty line stays one. Returns the lines.
      def fit(lines, width = @cols - 1)
        lines.flat_map do |l|
          next [''] if l.to_s.empty?

          indent = Modern::FrameBuffer.plain(l)[/\A */]
          first, *rest = wrap(l, width)
          next [first] if rest.empty?

          [first, *wrap(rest.join(' '), width - indent.size).map { |r| "#{indent}#{r}" }]
        end
      end

      # Writes +text+ (made #plain) as a paragraph in +color+, wrapped to
      # #width and indented by a space.
      #
      #   screen.say('Posted.', color: GN)
      def say(text, color: LG)
        wrap(plain(text)).each { |l| puts " #{color}#{l}#{LG}" }
      end

      # Reads a key (see Rubbs::Common::Line::Telnet#readkey): +:idle+ after +timeout+
      # seconds, when given. Raises IOError when the caller hangs up.
      def key(timeout: nil)
        k = @session.readkey(timeout: timeout)
        raise Common::Line::Hangup if k.nil?

        k
      end

      # Shows +lines+ (#fit to the screen) one #page_size at a time, each
      # page under the #title of +heading+ and +right+, waiting for RETURN
      # after each; q, ← or RUN/STOP leave early.
      #
      # [right]   the right end of the title bar
      # [wait]    false: the last page does not wait, and leaves +room+
      #           rows free for what follows (a command line)
      # [room]    the rows the last page leaves free with +wait+ false
      # [numbers] true: the title bar shows the page, <tt>2/5</tt>, after
      #           +right+
      #
      # Returns +nil+.
      def page(heading, lines, right: '', wait: true, room: 1, numbers: false)
        lines  = fit(lines)
        lines  = [" #{GR}#{EMPTY}#{LG}"] if lines.empty?
        chunks = lines.each_slice(wait ? page_size : page_size - room).to_a
        chunks.each_with_index do |chunk, i|
          title(heading, numbers ? "#{right}#{i + 1}/#{chunks.size}" : right)
          chunk.each { |l| puts l }
          break unless turn_page?(i == chunks.size - 1, wait)
        end
        nil
      end
    end
  end
end

require_relative 'screen/prompts'
require_relative 'screen/helpers'
