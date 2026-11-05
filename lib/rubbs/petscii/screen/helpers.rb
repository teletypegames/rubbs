# frozen_string_literal: true

module Rubbs
  module Petscii
    class Screen
      # The short sentences of a line-by-line board: a message, a question,
      # a number, a list to pick from again and again, a page of Markdown, a
      # QR code.
      module Helpers
        include Colors

        # Tells the caller +text+ in red (or +color+) under what is on the
        # screen and waits for a key.
        def alert(text, color: RD)
          puts
          say(text, color: color)
          pause
        end

        # Tells the caller +text+ in green and waits for a key.
        def notice(text)
          puts
          say(text, color: GN)
          pause
        end

        # A line the caller types after +label+ (white) and a <tt>></tt>,
        # with +hint+ dim above it when given. Returns the text stripped, or
        # +nil+ when it is empty.
        #
        #   query = prompt('title', hint: 'return alone: menu', max: 80)
        def prompt(label, hint: nil, text: '', max: nil, mask: nil)
          say(hint, color: GR) if hint
          answer = ask(" #{WH}#{label}#{LG}> ", text: text, max: max, mask: mask)
          answer.empty? ? nil : answer
        end

        # Asks +question+ with y/n. Returns whether the answer is yes.
        def confirm?(question) = choose(" #{question} #{DG}(y/n)#{LG} ", %w[y n], back: 'n') == 'y'

        # A whole number in +range+ typed after +label+, or +nil+ when the
        # answer is empty, not a number or not in it.
        def number(label, range, max: 6)
          value = prompt(label, max: max)
          value&.match?(/\A\d+\z/) && range.cover?(value.to_i) ? value.to_i : nil
        end

        # Lets the caller #pick from +items+ under +heading+ again and again,
        # running the block with each one picked, until they go back. A
        # Rubbs::Common::Line::Abort in the block leaves the caller at the list. +items+ may
        # be a callable, read again each round (a list that changes), and so
        # may an option (<tt>right: -> { "#{wall.size} works" }</tt>). +label+
        # names an item (a Symbol or a callable); +options+ are those of
        # #pick. Returns +nil+.
        #
        #   each_pick("SEARCH: #{query}", results, label: :title) { |r| read(r.title) }
        def each_pick(heading, items, label: :to_s, **options)
          label = label.to_proc
          loop do
            round  = options.transform_values { |v| v.is_a?(Proc) ? v.call : v }
            picked = pick(heading, items.respond_to?(:call) ? items.call : items, **round, &label)
            break if picked.nil?

            begin
              yield picked
            rescue Common::Line::Abort
              next
            end
          end
          nil
        end

        # +text+ (Markdown) as lines for this screen: in MARKDOWN's colours,
        # +width+ columns, +indent+ spaces before each.
        def markdown(text, width: @width, indent: 1)
          Common::Text::Markdown.to_lines(text, width: width, theme: MARKDOWN).map { |l| "#{' ' * indent}#{l}" }
        end

        # Writes +text+ (an address) as a QR code in the middle of the
        # screen: with a quiet zone when it fits, without one when only that
        # fits. Returns the lines written; when even that is too big, says so
        # and returns +nil+.
        def qr(text)
          code = qr_code(text)
          return alert('This address is too long for a QR code here.') && nil unless code

          indent = ' ' * [(@cols - 1 - Modern::FrameBuffer.visible_width(code.first)) / 2, 0].max
          code.each { |line| puts("#{indent}#{line}") }
        end

        private

        def qr_code(text)
          room = { cols: @cols - 1, rows: @rows - CHROME }
          Common::Text::QR.petscii(text, **room)
        rescue Common::Text::QR::TooLong
          begin
            Common::Text::QR.petscii(text, **room, quiet: 1)
          rescue Common::Text::QR::TooLong
            nil
          end
        end
      end

      include Helpers
    end
  end
end
