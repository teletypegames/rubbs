# frozen_string_literal: true

module BBS
  # The telnet line I/O of a BBS::Session: option negotiation, key and line
  # input with telnet commands filtered out, ANSI escape and mouse report
  # decoding, window size (NAWS) tracking, and the PETSCII mode for Commodore
  # 64 callers. The including class keeps the socket in +@client+.
  module Telnet
    # Telnet "interpret as command" byte, the start of every telnet command.
    IAC  = 255
    # Telnet WILL: the sender offers to use an option.
    WILL = 251
    # Telnet WONT: the sender refuses an option.
    WONT = 252
    # Telnet DO: the sender asks the other side to use an option.
    DO   = 253
    # Telnet DONT: the sender asks the other side not to use an option.
    DONT = 254
    # Telnet SB: start of a subnegotiation.
    SB   = 250
    # Telnet SE: end of a subnegotiation.
    SE   = 240

    # Telnet option BINARY (8-bit data, no CR NUL handling), asked for by
    # the file transfers.
    BINARY_OPT = 0
    # Telnet option ECHO (the server echoes what the caller types).
    ECHO_OPT = 1
    # Telnet option SUPPRESS-GO-AHEAD (character-at-a-time mode).
    SGA_OPT  = 3
    # Telnet option NAWS (the client reports its window size).
    NAWS_OPT = 31

    # The most bytes #readline keeps in a line; further characters are dropped.
    MAX_LINE = 1024
    # The widest terminal accepted from a NAWS report, in columns.
    MAX_COLS = 500
    # The tallest terminal accepted from a NAWS report, in rows.
    MAX_ROWS = 200
    # Seconds to wait for the rest of an escape sequence (or UTF-8
    # character) before a lone ESC counts as the Escape key.
    ESC_WAIT = 0.15
    # Turns xterm mouse reporting on: button events with drags (1002) in SGR
    # coordinates (1006).
    MOUSE_ON  = "\e[?1002h\e[?1006h"
    # Turns every xterm mouse reporting mode #enable_mouse may leave on off.
    MOUSE_OFF = "\e[?1006l\e[?1002l\e[?1000l"
    # The terminal width assumed while the caller has not reported one.
    DEFAULT_COLS = 80
    # The terminal height assumed while the caller has not reported one.
    DEFAULT_ROWS = 24
    # The narrowest terminal accepted from a NAWS report, in columns.
    MIN_COLS = 20
    # The shortest terminal accepted from a NAWS report, in rows.
    MIN_ROWS = 8
    # The bytes of a NAWS report: width and height, two bytes each.
    NAWS_SIZE = 4
    # The most bytes of a subnegotiation kept; the rest is read and dropped.
    MAX_SUBNEGOTIATION = 64

    # The control bytes Ctrl-A ... Ctrl-Z.
    CTRL_LETTERS = 0x01..0x1a
    # Added to a Ctrl-letter byte, gives its lowercase letter.
    CTRL_TO_LETTER = 0x60
    # The bytes that start a multibyte UTF-8 character.
    UTF8_LEAD = 0xc2..0xf4
    # The lowest lead byte of a four-byte UTF-8 character.
    UTF8_LEAD_4 = 0xf0
    # The lowest lead byte of a three-byte UTF-8 character.
    UTF8_LEAD_3 = 0xe0
    # The bits that tell a UTF-8 continuation byte.
    UTF8_TAIL_MASK = 0xc0
    # The value of those bits in a continuation byte.
    UTF8_TAIL = 0x80
    # Takes back the last character on the caller's screen: back, space,
    # back.
    ERASE = "\b \b"

    # The second byte of an ESC sequence that starts an SS3 sequence.
    SS3_START = 'O'
    # The final bytes of the cursor keys, the same after CSI and SS3.
    CURSOR_KEYS = { 'A' => :up, 'B' => :down, 'C' => :right, 'D' => :left,
                    'H' => :home, 'F' => :end }.freeze
    # The keys sent as SS3 and a final byte: the cursor keys and F1-F4.
    SS3_KEYS = CURSOR_KEYS.merge('P' => :f1, 'Q' => :f2, 'R' => :f3, 'S' => :f4).freeze
    # The keys sent as CSI and a letter: the cursor keys and Shift-Tab.
    CSI_KEYS = CURSOR_KEYS.merge('Z' => :shift_tab).freeze
    # The final byte of a CSI key sent as a number: <tt>ESC [ 15 ~</tt>.
    TILDE = '~'
    # The keys sent as <tt>ESC [ number ~</tt>, by number.
    TILDE_KEYS = {
      1 => :home, 7 => :home, 2 => :insert, 3 => :delete, 4 => :end, 8 => :end,
      5 => :page_up, 6 => :page_down,
      11 => :f1, 12 => :f2, 13 => :f3, 14 => :f4, 15 => :f5, 17 => :f6,
      18 => :f7, 19 => :f8, 20 => :f9, 21 => :f10, 23 => :f11, 24 => :f12
    }.freeze

    # The final byte of an X10 mouse report, <tt>ESC [ M b x y</tt>, and of
    # an SGR mouse press.
    MOUSE_PRESS = 'M'
    # The final byte of an SGR mouse release.
    MOUSE_RELEASE = 'm'
    # The parameter prefix of an SGR mouse report, <tt>ESC [ < b ; x ; y</tt>.
    SGR_MOUSE = '<'
    # The number of fields of an SGR mouse report: button, x, y.
    SGR_MOUSE_FIELDS = 3
    # Added to each byte of an X10 mouse report.
    X10_OFFSET = 32
    # The bits of a mouse report that tell the button.
    MOUSE_BUTTON_BITS = 3
    # The button value of an X10 release report (no button).
    X10_RELEASE = 3
    # Mouse report bit: Shift was held.
    MOUSE_SHIFT = 4
    # Mouse report bit: Meta (Alt) was held.
    MOUSE_META = 8
    # Mouse report bit: Ctrl was held.
    MOUSE_CTRL = 16
    # Mouse report bit: the mouse moved with a button held.
    MOUSE_MOTION = 32
    # Mouse report bit: a wheel turn; button 0 is up, 1 is down.
    MOUSE_WHEEL = 64
    # The buttons by the value of MOUSE_BUTTON_BITS; any other is +:none+.
    MOUSE_BUTTONS = %i[left middle right].freeze

    # A decoded mouse report.
    #
    # [kind]   +:press+, +:release+, +:move+ (motion with a button held) or
    #          +:wheel+
    # [button] +:left+, +:middle+, +:right+ or +:none+; for +:wheel+, +:up+
    #          or +:down+
    # [x, y]   1-based terminal column and row
    # [mods]   Array of the modifiers held: +:shift+, +:meta+, +:ctrl+
    MouseEvent = Struct.new(:kind, :button, :x, :y, :mods, keyword_init: true)

    # Sets the terminal size to 80x24 until the client reports its own, and
    # sends the opening negotiation: the server will echo and suppress
    # go-ahead, and asks the client to suppress go-ahead and report its
    # window size (NAWS).
    #
    # A line end goes first: the UltimateTerm of the C64 Ultimate takes a
    # line whose first byte is a telnet command (IAC) for ASCII with ANSI and
    # translates every byte from ASCII to PETSCII, which turns CLR into
    # nothing and swaps the case of letters both ways; any other first byte
    # leaves it on PETSCII, printing the bytes as they come.
    def negotiate
      @term_cols = 80
      @term_rows = 24
      send_raw Ansi::CRLF
      send_raw [IAC, WILL, SGA_OPT].pack('C*')
      send_raw [IAC, WILL, ECHO_OPT].pack('C*')
      send_raw [IAC, DO,   SGA_OPT].pack('C*')
      send_raw [IAC, DO,   NAWS_OPT].pack('C*')
    end

    # Turns on xterm mouse reporting (button events, drags, SGR coordinates)
    # by writing the escape sequences. Does nothing when it is already on or
    # the line is in PETSCII mode.
    def enable_mouse
      return if @mouse_enabled || @petscii
      # 1002: presses, releases and motion while a button is held (drags).
      write MOUSE_ON
      @mouse_enabled = true
    end

    # Turns xterm mouse reporting off, if #enable_mouse turned it on.
    def disable_mouse
      return unless @mouse_enabled
      write MOUSE_OFF
      @mouse_enabled = false
    end

    # Reads one key press, skipping telnet commands (a NAWS report among
    # them updates the window size). Returns:
    #
    # - a one-character String for a printable character (UTF-8 included),
    # - a Symbol for a special key: +:enter+, +:tab+, +:backspace+,
    #   +:escape+, +:interrupt+ (Ctrl-C), <tt>:ctrl_a</tt> ... <tt>:ctrl_z</tt>,
    #   arrows, +:home+, +:end+, +:page_up+, +:f1+ ... +:f12+ and the like,
    #   with an <tt>alt_</tt>, <tt>shift_</tt>, <tt>ctrl_</tt> or
    #   <tt>ctrl_shift_</tt> prefix for modified keys,
    # - a MouseEvent for a mouse report,
    # - +:idle+ when nothing came within +timeout+ seconds,
    # - +nil+ when the client hung up.
    #
    # On a PETSCII line the keys come from BBS::Petscii.key. CR LF and CR NUL
    # count as one +:enter+. +timeout+ +nil+ waits forever.
    def readkey(timeout: nil)
      loop do
        raw  = read_byte(timeout)
        return :idle if raw == :timeout
        return nil if raw.nil?
        byte = raw.ord

        if byte == IAC
          absorb_iac
          next
        end

        if @petscii
          key = Petscii.key(byte)
          next if key.nil?
          return key
        end

        # CR LF and CR NUL are one Enter, not two.
        after_cr  = @after_cr
        @after_cr = byte == Ascii::CR
        next if after_cr && (byte == Ascii::LF || byte == Ascii::NUL)

        case byte
        when Ascii::CR, Ascii::LF  then return :enter
        when Ascii::TAB            then return :tab
        when Ascii::ESC            then return read_escape_sequence
        when Ascii::BS, Ascii::DEL then return :backspace
        when Ascii::ETX            then return :interrupt
        when CTRL_LETTERS          then return :"ctrl_#{(byte + CTRL_TO_LETTER).chr}"
        when Ascii::PRINTABLE      then return raw.force_encoding(Encoding::UTF_8)
        when UTF8_LEAD
          char = read_utf8(raw)
          return char if char
        end
      end
    end

    # Reads one raw byte from the socket as a one-byte String. With a
    # +timeout+ in seconds, returns +:timeout+ when nothing arrives in time.
    # Returns +nil+ on hangup.
    def read_byte(timeout = nil)
      return @client.read(1) if timeout.nil?
      ready = IO.select([@client], nil, nil, timeout)
      return :timeout unless ready
      @client.read(1)
    end

    # Reads one byte of the line as an Integer, for binary protocols
    # (ZMODEM): telnet commands are taken out and a doubled IAC comes back as
    # 255. Returns +:timeout+ when nothing came within +timeout+ seconds and
    # +nil+ on hangup.
    def read_raw_byte(timeout)
      loop do
        raw = read_byte(timeout)
        return raw if raw.nil? || raw == :timeout
        return raw.ord unless raw.ord == IAC

        cmd = @client.read(1)
        return nil if cmd.nil?
        return IAC if cmd.ord == IAC

        absorb_iac(cmd)
      end
    end

    # Reads a line typed by the caller, echoing it back, and returns it as a
    # UTF-8 String without the line end (invalid bytes removed), or +nil+ on
    # hangup. Backspace deletes the last character; control characters and
    # bytes beyond MAX_LINE are ignored. ENTER writes a CRLF.
    #
    # [mask] when given, echoed in place of each character (for passwords,
    #        e.g. <tt>'*'</tt>); +nil+ echoes the characters themselves
    def readline(mask: nil)
      line = +''.b

      loop do
        raw  = @client.read(1)
        return nil if raw.nil?
        byte = raw.ord

        if byte == IAC
          absorb_iac
          next
        end

        if @petscii
          line = petscii_edit(line, Petscii.key(byte), mask)
          return line if line.encoding == Encoding::UTF_8
          next
        end

        after_cr  = @after_cr
        @after_cr = byte == Ascii::CR
        next if after_cr && (byte == Ascii::LF || byte == Ascii::NUL)

        if byte == Ascii::CR || byte == Ascii::LF
          write Ansi::CRLF
          return line.force_encoding(Encoding::UTF_8).scrub('')
        end

        if byte == Ascii::BS || byte == Ascii::DEL
          unless line.empty?
            text = line.dup.force_encoding(Encoding::UTF_8)
            line = (text.valid_encoding? ? text.chop : text.byteslice(0, text.bytesize - 1)).b
            write ERASE
          end
          next
        end

        next if byte < Ascii::SPACE || line.bytesize >= MAX_LINE

        line << raw
        echo = if mask.nil? then raw
               elsif (byte & UTF8_TAIL_MASK) == UTF8_TAIL then ''
               else mask
               end
        write(echo)
      end
    end

    # Returns true once the client has reported its window size (telnet
    # NAWS). Real terminals do; port scanners and password-guessing bots
    # usually do not.
    def naws_reported?
      @naws_reported == true
    end

    # Waits up to +timeout+ seconds for the client's answers to the
    # negotiation, its window size above all, and drops whatever it types
    # meanwhile: a bot's "root" sent before any prompt goes nowhere. True
    # when the window size came.
    def settle(timeout: 1.5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until naws_reported?
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if left <= 0 || !IO.select([@client], nil, nil, left)

        raw = @client.read(1)
        break if raw.nil?

        absorb_iac if raw.ord == IAC
      end
      naws_reported?
    end

    # Switches the line to PETSCII for a Commodore 64 (see BBS::Petscii):
    # sets the size to 40x25, sends the codes for the lowercase character set
    # (locked) and a clear screen, and turns mouse reporting off. From then on
    # #write encodes its output and #readkey / #readline decode PETSCII keys.
    # Does nothing when the line is already in PETSCII mode.
    def petscii!
      return if @petscii

      @mouse_enabled = false
      @term_cols     = Petscii::COLS
      @term_rows     = Petscii::ROWS
      send_raw Petscii.bytes("#{Petscii::LOWERCASE}#{Petscii::LOCK_CASE}#{Petscii::CLEAR}")
      @petscii = Petscii::Encoder.new
    end

    # True when the line is in PETSCII mode (see #petscii!).
    def petscii? = !@petscii.nil?

    # Returns the caller's socket itself, for a door that hands it on as it
    # is (BBS::Gateway).
    def line = @client

    # Sets the caller's window size from a NAWS report: +cols+ is clamped to
    # 20..MAX_COLS and +rows+ to 8..MAX_ROWS, a zero value is ignored, and a
    # PETSCII line keeps 40x25. Marks the size as reported (#naws_reported?).
    def resize!(cols, rows)
      unless @petscii
        @term_cols = cols.clamp(MIN_COLS, MAX_COLS) if cols.positive?
        @term_rows = rows.clamp(MIN_ROWS, MAX_ROWS) if rows.positive?
      end
      @naws_reported = true
    end

    # Writes +data+ (a String) to the caller, encoded to PETSCII on a
    # PETSCII line. Errors are swallowed: returns +nil+ when the write fails.
    def write(data)
      @client.write(@petscii ? @petscii.encode(data) : data)
    rescue StandardError
      nil
    end

    # Writes the bytes of +data+ to the caller as they are, not encoded to
    # PETSCII even on a PETSCII line: for binary protocols (BBS::Zmodem,
    # BBS::Xmodem) and telnet commands. Errors are swallowed: returns +nil+
    # when the write fails.
    def write_raw(data) = send_raw(data)

    private

    # Reads a CSI / SS3 sequence after ESC. Returns a Symbol (key name),
    # a Symbol :"alt_<x>" (Alt-modified key), a MouseEvent, or :escape.
    def read_escape_sequence
      return :escape unless IO.select([@client], nil, nil, ESC_WAIT)

      b1 = @client.read(1)
      return :escape if b1.nil?

      case b1
      when Ansi::CSI_BYTE
        read_csi
      when SS3_START
        # SS3 — many terminals send F1-F4 this way
        b2 = @client.read(1)
        return :escape if b2.nil?
        SS3_KEYS.fetch(b2, :escape)
      when Ansi::CR
        @after_cr = true
        :alt_enter
      else
        # Treat ESC + printable as Alt+<char>
        if Ascii::PRINTABLE.cover?(b1.ord)
          :"alt_#{b1.downcase}"
        else
          :escape
        end
      end
    end

    def read_csi
      # Read CSI parameters: digits, ';', '<', '?', then a single final byte.
      raw = +''
      final = nil
      loop do
        c = @client.read(1)
        return :escape if c.nil?
        if c.match?(Ansi::CSI_FINAL)
          final = c
          break
        end
        raw << c
        break if raw.length > Ansi::MAX_CSI_LENGTH # safety
      end
      return :escape if final.nil?

      # X10 mouse report (no SGR 1006 support): ESC [ M b x y, each plus 32.
      if final == MOUSE_PRESS && raw.empty?
        b, x, y = 3.times.map { @client.read(1)&.ord.to_i - X10_OFFSET }
        return decode_mouse(b, x, y, pressed: (b & MOUSE_BUTTON_BITS) != X10_RELEASE)
      end

      # SGR mouse: ESC [ < b ; x ; y (M|m)
      if raw.start_with?(SGR_MOUSE) && (final == MOUSE_PRESS || final == MOUSE_RELEASE)
        parts = raw[1..].split(';')
        return :escape if parts.size != SGR_MOUSE_FIELDS
        b = parts[0].to_i
        x = parts[1].to_i
        y = parts[2].to_i
        return decode_mouse(b, x, y, pressed: final == MOUSE_PRESS)
      end

      with_modifier(csi_key(final, raw), raw)
    end

    # xterm reports Shift, Alt and Ctrl as a second parameter: ESC [ 1 ; 2 A
    # is Shift-Up, ESC [ 15 ; 5 ~ is Ctrl-F5.
    MODIFIERS = { 2 => 'shift', 3 => 'alt', 5 => 'ctrl', 6 => 'ctrl_shift' }.freeze

    def with_modifier(key, raw)
      prefix = MODIFIERS[raw.split(';')[1].to_i]
      return key unless prefix && key.is_a?(Symbol) && key != :escape

      :"#{prefix}_#{key}"
    end

    def csi_key(final, raw)
      return TILDE_KEYS.fetch(raw.to_i, :escape) if final == TILDE

      CSI_KEYS.fetch(final, :escape)
    end

    # The rest of a UTF-8 character whose first byte is `lead`; nil when
    # the bytes do not make one.
    def read_utf8(lead)
      bytes = lead.b
      (lead.ord >= UTF8_LEAD_4 ? 3 : lead.ord >= UTF8_LEAD_3 ? 2 : 1).times do
        return nil unless IO.select([@client], nil, nil, ESC_WAIT)

        nxt = @client.read(1)
        return nil if nxt.nil? || (nxt.ord & UTF8_TAIL_MASK) != UTF8_TAIL

        bytes << nxt
      end
      char = bytes.force_encoding(Encoding::UTF_8)
      char.valid_encoding? ? char : nil
    end

    def decode_mouse(b, x, y, pressed:)
      mods = []
      mods << :shift if b & MOUSE_SHIFT != 0
      mods << :meta  if b & MOUSE_META != 0
      mods << :ctrl  if b & MOUSE_CTRL != 0

      motion = (b & MOUSE_MOTION) != 0
      wheel  = (b & MOUSE_WHEEL) != 0

      button_id = b & MOUSE_BUTTON_BITS
      if wheel
        kind   = :wheel
        button = button_id == 0 ? :up : :down
      else
        button = MOUSE_BUTTONS.fetch(button_id, :none)
        kind = motion ? :move : (pressed ? :press : :release)
      end

      MouseEvent.new(kind: kind, button: button, x: x, y: y, mods: mods)
    end

    def absorb_iac(cmd = @client.read(1))
      return if cmd.nil?

      case cmd.ord
      when SB
        opt = @client.read(1)
        buf = []
        loop do
          b = @client.read(1)
          break if b.nil?
          if b.ord == IAC
            s = @client.read(1)
            break if s.nil? || s.ord == SE
            buf << IAC if s.ord == IAC && buf.size < MAX_SUBNEGOTIATION
          elsif buf.size < MAX_SUBNEGOTIATION
            buf << b.ord
          end
        end
        if opt&.ord == NAWS_OPT && buf.size >= NAWS_SIZE
          resize!((buf[0] << 8) | buf[1], (buf[2] << 8) | buf[3])
        end
      when WILL, WONT, DO, DONT
        @client.read(1)
      end
    end

    # One key of readline on a C64: the line so far (binary) while it goes
    # on, the finished line (UTF-8) on RETURN.
    def petscii_edit(line, key, mask)
      case key
      when :enter
        write Ansi::CRLF
        return line.dup.force_encoding(Encoding::UTF_8).scrub('')
      when :backspace
        unless line.empty?
          line = line.dup.force_encoding(Encoding::UTF_8).chop.b
          write ERASE
        end
      when String
        if line.bytesize < MAX_LINE
          line = line + key.b
          write(mask.nil? ? key : mask)
        end
      end
      line
    end

    def send_raw(data)
      @client.write(data)
    rescue StandardError
      nil
    end
  end
end
