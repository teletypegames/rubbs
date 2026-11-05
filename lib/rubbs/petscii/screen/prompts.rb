# frozen_string_literal: true

module Rubbs
  module Petscii
    class Screen
      # What a Screen asks the caller: a key (#choose, #pause), a line
      # (#ask), a text (#edit), and the menus, which are Rubbs::Common::Screens::Selector
      # configurations (#pick, #menu, #actions).
      module Prompts
        include Colors

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

        # Writes +prompt+ and reads a line in a Rubbs::Common::Screens::Field after it, as wide
        # as the rest of the screen, starting from +text+; +mask+ hides what
        # is typed, +max+ limits its length.
        #
        # Returns the line, stripped; empty when the caller cancelled with
        # RUN/STOP or ←.
        def ask(prompt, text: '', mask: nil, max: nil)
          Common::Screens::Field.ask(@session, prompt, text: text, max: max, mask: mask, cols: @cols).to_s.strip
        end

        # +text+ edited in the full-screen Rubbs::Common::Screens::Editor at this screen's size,
        # titled +title+; +single_line+ makes it one paragraph that RETURN
        # saves, +max+ limits its length. With +autosave+ seconds and a block
        # the block gets the text whenever it changed, every +autosave+
        # seconds and when the caller hangs up (see Rubbs::Common::Screens::Editor.new). The
        # screen is left as the editor leaves it.
        #
        # Returns the text when saved, +nil+ when the caller quit.
        def edit(text = '', title:, single_line: false, max: nil, autosave: nil, &on_autosave)
          Common::Screens::Editor.new(
            @session,
            text: text, title: title, single_line: single_line, max: max,
                                           cols: @cols, rows: @rows, autosave: autosave,
            &on_autosave
          ).run
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

        # A numbered list of +items+, each labelled by the block (made
        # #plain; default +to_s+), under the #title of +heading+ and +right+: a
        # Rubbs::Common::Screens::Selector.list a #page_size high. CRSR and
        # RETURN or the number pick, CRSR left and right turn the pages.
        #
        # [empty]    shown, with a #pause, when +items+ is empty
        # [commands] single-key commands, <tt>{ 's' => 'search' }</tt>: the
        #            hint row lists them, and pressing one returns its key
        # [item_commands] single-key commands on the lit item,
        #            <tt>{ 'd' => 'discard' }</tt>: the hint row lists them,
        #            and pressing one returns <tt>[key, item]</tt>
        #
        # Returns the item picked, a +commands+ key, an
        # <tt>[item_commands key, item]</tt> pair, or +nil+ for q, ← or
        # RUN/STOP (and for no items).
        def pick(heading, items, empty: EMPTY, right: '', commands: {}, item_commands: {}, &label)
          label ||= :to_s.to_proc
          title(heading, right)
          if items.empty?
            say(empty, color: GR)
            pause
            return nil
          end
          Common::Screens::Selector.list(
            @session,
            items,
            width:      @cols - 1,
            height:     page_size,
            hint:       pick_hint(commands.merge(item_commands)),
            exits:      commands.keys.to_h { |k| [k, k] }.merge('q' => nil),
            item_exits: item_commands.keys.to_h { |k| [k, k] }
          ) do |item|
            plain(label.call(item))
          end
        end

        # A Rubbs::Common::Screens::Selector of +items+ (Rubbs::Common::Screens::Selector::Item) at the cursor, the
        # screen's width less one. The other options are
        # those of Rubbs::Common::Screens::Selector.new.
        #
        # Returns the value of the item taken, or +back+ for ← or RUN/STOP.
        def menu(items, back: nil, **)
          Common::Screens::Selector.new(@session, items, width: @cols - 1, back: back, **).run
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
          menu(actions.map { |k, label| Common::Screens::Selector.item(label, key: k, value: k) }, across: true, back: 'q')
        end

        private

        # The hint row of #pick: its commands, or PICK_HINT.
        def pick_hint(commands)
          commands.empty? ? PICK_HINT : "#{commands.map { |k, v| "#{k}: #{v}" }.join('  ')}  q: back"
        end

        # Waits under a page of #page: whether to show the next one. The last
        # page waits only with +wait+; q, ← or RUN/STOP leave early.
        def turn_page?(last, wait)
          return false if last && !wait

          key = pause(last ? 'return: back' : 'return: more  q: back')
          !last && key != :escape && key.to_s.downcase != 'q'
        end
      end

      include Prompts
    end
  end
end
