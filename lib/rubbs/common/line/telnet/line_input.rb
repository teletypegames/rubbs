# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      module Telnet
        # Line input of a telnet line: #readline echoes what the caller types,
        # with Backspace, on an ANSI terminal and a Commodore 64 alike.
        module LineInput
          # The most bytes #readline keeps in a line; further characters are
          # dropped.
          MAX_LINE = 1024
          # Takes back the last character on the caller's screen: back, space,
          # back.
          ERASE = "\b \b"

          # Reads a line typed by the caller, echoing it back, and returns it as
          # a UTF-8 String without the line end (invalid bytes removed), or +nil+
          # on hangup. Backspace deletes the last character; control characters
          # and bytes beyond MAX_LINE are ignored. ENTER writes a CRLF.
          #
          # [mask] when given, echoed in place of each character (for passwords,
          #        e.g. <tt>'*'</tt>); +nil+ echoes the characters themselves
          def readline(mask: nil)
            line = +''.b
            loop do
              raw  = @client.read(1) or return nil
              byte = telnet_data(raw.ord) or next
              done = edit_line(line, line_key(byte), mask)
              return done if done
            end
          end

          private

          # What +byte+ does to the line: +:enter+, +:backspace+, a character to
          # add (a String), or +nil+.
          def line_key(byte)
            return Petscii.key(byte) if @petscii
            return if line_end_pair?(byte)

            key = Keys::CONTROL_KEYS[byte]
            return key if %i[enter backspace].include?(key)

            byte.chr if byte >= Ascii::SPACE
          end

          # Applies +key+ to +line+ (a binary String, changed in place). Returns
          # the finished line on +:enter+, else +nil+.
          def edit_line(line, key, mask)
            case key
            when :enter     then finish_line(line)
            when :backspace then erase_char(line)
            when String     then type_char(line, key, mask)
            end
          end

          def finish_line(line)
            write Modern::Ansi::CRLF
            line.dup.force_encoding(Encoding::UTF_8).scrub('')
          end

          def erase_char(line)
            return if line.empty?

            text = line.dup.force_encoding(Encoding::UTF_8)
            line.replace((text.valid_encoding? ? text.chop : text.byteslice(0...-1)).b)
            write ERASE
            nil
          end

          def type_char(line, char, mask)
            return if line.bytesize >= MAX_LINE

            line << char.b
            write(echo_of(char, mask))
            nil
          end

          # A UTF-8 continuation byte adds no character, so no mask either.
          def echo_of(char, mask)
            return char if mask.nil?

            utf8_tail?(char.b.getbyte(0)) ? '' : mask
          end
        end
      end
    end
  end
end
