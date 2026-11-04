# frozen_string_literal: true

module BBS
  class Gateway
    # The translation a gateway puts on the line when a PETSCII caller (a
    # Commodore 64) dials a board made for ASCII and ANSI terminals. The
    # board's bytes go down as PETSCII: text in UTF-8, or CP437 from the
    # first bytes that are not UTF-8 on, through a Petscii::Encoder, so
    # letters swap case, ANSI colours and cursor moves become C64 control
    # codes and line drawing the nearest glyph. The C64's keys go up as an
    # ANSI terminal sends them.
    #
    #   bridge = BBS::Gateway::AsciiBridge.new
    #   bridge.down("Hello\r\n")   # PETSCII bytes for the C64
    #   bridge.up("\x91".b)        # => "\e[A" (CRSR up)
    class AsciiBridge
      # The C64's special keys (BBS::Petscii.key) as an ANSI terminal sends
      # them; a key not listed (F1-F8) is not sent.
      KEYS = {
        enter:     "\r",
        backspace: "\b",
        escape:    "\e",
        up:        "\e[A",
        down:      "\e[B",
        right:     "\e[C",
        left:      "\e[D",
        home:      "\e[H"
      }.freeze
      # Signs the C64 has a key for and ASCII has not, as their ASCII stand-in.
      SIGNS = { '£' => '#' }.freeze
      # The telnet IAC byte, doubled in what goes down so the caller's
      # telnet client takes it as data.
      IAC = "\xFF".b
      # The first byte of a UTF-8 sequence of two, three and four bytes.
      UTF8_LEADS = { 0xF0 => 4, 0xE0 => 3, 0xC0 => 2 }.freeze

      # Creates a bridge with a fresh encoder and no partial character.
      def initialize
        @encoder = Petscii::Encoder.new
        @pending = +''.b
        @cp437   = false
      end

      # Returns the PETSCII bytes for +bytes+ the board sent (telnet
      # commands already taken out). While the board writes UTF-8, a
      # character cut at the end of +bytes+ waits for the next call; the
      # encoder's column and colour carry over too.
      def down(bytes)
        data     = @pending + bytes.b
        @pending = @cp437 ? +''.b : cut_character(data)
        whole    = data.byteslice(0, data.bytesize - @pending.bytesize)
        @encoder.encode(text(whole)).gsub(IAC, IAC + IAC)
      end

      # Returns the bytes an ANSI terminal would send for +bytes+, the keys
      # the C64 sent: letters in ASCII case, RETURN as CR, DEL as backspace,
      # the cursor keys as ANSI sequences, RUN/STOP as ESC.
      def up(bytes) = bytes.b.each_byte.filter_map { |byte| key(Petscii.key(byte)) }.join.b

      private

      def key(key) = key.is_a?(Symbol) ? KEYS[key] : SIGNS.fetch(key, key)

      def text(data)
        utf8 = data.dup.force_encoding(Encoding::UTF_8)
        return utf8 if utf8.valid_encoding?

        @cp437 = true
        data.dup.force_encoding(Encoding::IBM437).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      # The bytes at the end of +data+ that begin a UTF-8 character but do
      # not finish it, or an empty String.
      def cut_character(data)
        tail = data.byteslice([data.bytesize - 3, 0].max..)
        lead = tail.bytes.rindex { |byte| byte >= 0xC0 }
        return +''.b unless lead

        length = UTF8_LEADS.find { |first, _| tail.getbyte(lead) >= first }.last
        tail.bytesize - lead < length ? tail.byteslice(lead..) : +''.b
      end
    end
  end
end
