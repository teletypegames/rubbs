# frozen_string_literal: true

require_relative 'colors'

module BBS
  module Petscii
    # The screen of one call on a line-by-line board, and the ways such a
    # board talks: a reversed title bar, pages of text that wait for RETURN,
    # numbered cursor lists (BBS::Selector), single-key and cursor menus, a
    # line field (BBS::Field) and the full-screen editor (BBS::Editor).
    #
    # It is made for a Commodore 64, a 40×25 screen on a session switched
    # with <tt>session.petscii!</tt>, which makes PETSCII of what the screen
    # writes. Given +cols+ and +rows+ it serves a modern terminal too: on a
    # session that is not PETSCII, #cls homes the cursor and the text is
    # not made #plain.
    #
    # The colours are the ANSI constants of BBS::Petscii::Colors, included,
    # so a subclass writes +WH+, +LG+ … bare. A board subclasses it for
    # methods of its own:
    #
    #   class Screen < BBS::Petscii::Screen
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
      MODERN_CLEAR = "#{Ansi::RESET}#{Ansi::CLEAR}".freeze

      # The session written to and read from (BBS::Session or one that
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
      def cls = write(petscii? ? Petscii::CLEAR : MODERN_CLEAR)

      # Rings the bell.
      def bell = write("\a")

      # Clears the screen and writes the #title_bar of +text+ and +right+.
      def title(text, right = '')
        cls
        puts title_bar(text, right)
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

      # +text+ word-wrapped to +width+ columns, ANSI colours kept: an Array
      # of lines (BBS::FrameBuffer.wrap_ansi).
      def wrap(text, width = @width) = FrameBuffer.wrap_ansi(text.to_s, width)

      # +text+ in characters the C64 shows one to a cell (BBS::Petscii.plain)
      # on a PETSCII session; as it is on a modern one.
      def plain(text) = petscii? ? Petscii.plain(text) : text.to_s

      # Every line of +lines+ cut to +width+, the long ones wrapped under
      # their own indent. An empty line stays one. Returns the lines.
      def fit(lines, width = @cols - 1)
        lines.flat_map do |l|
          next [''] if l.to_s.empty?

          indent = FrameBuffer.plain(l)[/\A */]
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

      # Reads a key (see BBS::Telnet#readkey): +:idle+ after +timeout+
      # seconds, when given. Raises IOError when the caller hangs up.
      def key(timeout: nil)
        k = @session.readkey(timeout: timeout)
        raise IOError, 'the caller hung up' if k.nil?

        k
      end

      # Writes +prompt+ on a new line and waits for one of +keys+ (lowercase
      # letters, or key symbols); ← and RUN/STOP (Esc) give +back+. Echoes
      # the letter taken in capitals and ends the line.
      #
      # Returns the key taken, downcased.
      def choose(prompt, keys, back: 'q')
        write "\r\n#{prompt}"
        loop do
          k = key
          k = back if k == :escape
          k = k.downcase if k.is_a?(String)
          next unless keys.include?(k)

          puts(k.is_a?(String) ? k.upcase : '')
          return k
        end
      end

      # Writes +prompt+ and reads a line in a BBS::Field after it, as wide
      # as the rest of the screen, starting from +text+; +mask+ hides what
      # is typed, +max+ limits its length.
      #
      # Returns the line, stripped; empty when the caller cancelled with
      # RUN/STOP or ←.
      def ask(prompt, text: '', mask: nil, max: nil)
        Field.ask(@session, prompt, text: text, max: max, mask: mask, cols: @cols).to_s.strip
      end

      # +text+ edited in the full-screen BBS::Editor at this screen's size,
      # titled +title+; +single_line+ makes it one paragraph that RETURN
      # saves, +max+ limits its length. The screen is left as the editor
      # leaves it.
      #
      # Returns the text when saved, +nil+ when the caller quit.
      def edit(text = '', title:, single_line: false, max: nil)
        Editor.new(@session, text: text, title: title, single_line: single_line, max: max,
                             cols: @cols, rows: @rows).run
      end

      # Writes +text+ dim on a new line and waits for a key.
      #
      # Returns the key.
      def pause(text = 'return: back')
        write "\r\n #{DG}#{text}#{LG} "
        k = key
        puts
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
          last = i == chunks.size - 1
          next if last && !wait

          k = pause(last ? 'return: back' : 'return: more  q: back')
          break if !last && (k == :escape || k.to_s.downcase == 'q')
        end
        nil
      end

      # A numbered list of +items+, each labelled by the block (made
      # #plain; default +to_s+), under the #title of +heading+ and +right+: a
      # BBS::Selector.list a #page_size high. CRSR and
      # RETURN or the number pick, CRSR left and right turn the pages.
      #
      # [empty]    shown, with a #pause, when +items+ is empty
      # [commands] single-key commands, <tt>{ 's' => 'search' }</tt>: the
      #            hint row lists them, and pressing one returns its key
      #
      # Returns the item picked, a +commands+ key, or +nil+ for q, ← or
      # RUN/STOP (and for no items).
      def pick(heading, items, empty: EMPTY, right: '', commands: {}, &label)
        label ||= :to_s.to_proc
        title(heading, right)
        if items.empty?
          say(empty, color: GR)
          pause
          return nil
        end
        hint = commands.empty? ? PICK_HINT : "#{commands.map { |k, v| "#{k}: #{v}" }.join('  ')}  q: back"
        Selector.list(@session, items, width: @cols - 1, height: page_size, hint: hint,
                                       exits: commands.keys.to_h { |k| [k, k] }.merge('q' => nil)) do |item|
          plain(label.call(item))
        end
      end

      # A BBS::Selector of +items+ (BBS::Selector::Item) at the cursor, the
      # screen's width less one. The other options are
      # those of BBS::Selector.new.
      #
      # Returns the value of the item taken, or +back+ for ← or RUN/STOP.
      def menu(items, back: nil, **)
        Selector.new(@session, items, width: @cols - 1, back: back, **).run
      end

      # The keys of +actions+, <tt>[key, label]</tt> pairs, as a #menu on
      # one row under what is on the screen (after a line end), the cursor
      # moving along it.
      #
      #   case screen.actions(%w[d download], %w[q back])
      #   when 'd' then download
      #   end
      #
      # Returns the key taken; <tt>'q'</tt> for ← or RUN/STOP.
      def actions(*actions)
        puts
        menu(actions.map { |k, label| Selector.item(label, key: k, value: k) }, across: true, back: 'q')
      end
    end
  end
end
