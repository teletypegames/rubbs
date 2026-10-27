# frozen_string_literal: true

module BBS
  module Telnet
    IAC  = 255
    WILL = 251
    WONT = 252
    DO   = 253
    DONT = 254
    SB   = 250
    SE   = 240

    ECHO_OPT = 1
    SGA_OPT  = 3
    NAWS_OPT = 31

    MAX_LINE = 1024
    MAX_COLS = 500
    MAX_ROWS = 200
    ESC_WAIT = 0.15

    MouseEvent = Struct.new(:kind, :button, :x, :y, :mods, keyword_init: true)

    def negotiate
      @term_cols = 80
      @term_rows = 24
      send_raw [IAC, WILL, SGA_OPT].pack('C*')
      send_raw [IAC, WILL, ECHO_OPT].pack('C*')
      send_raw [IAC, DO,   SGA_OPT].pack('C*')
      send_raw [IAC, DO,   NAWS_OPT].pack('C*')
    end

    def enable_mouse
      return if @mouse_enabled || @petscii
      # 1002: presses, releases and motion while a button is held (drags).
      write "\e[?1002h\e[?1006h"
      @mouse_enabled = true
    end

    def disable_mouse
      return unless @mouse_enabled
      write "\e[?1006l\e[?1002l\e[?1000l"
      @mouse_enabled = false
    end

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
        @after_cr = byte == 13
        next if after_cr && (byte == 10 || byte == 0)

        case byte
        when 13, 10  then return :enter
        when 9       then return :tab
        when 27      then return read_escape_sequence
        when 8, 127  then return :backspace
        when 3       then return :interrupt
        when 1..26   then return :"ctrl_#{(byte + 96).chr}"
        when 32..126 then return raw.force_encoding(Encoding::UTF_8)
        when 0xc2..0xf4
          char = read_utf8(raw)
          return char if char
        end
      end
    end

    def read_byte(timeout = nil)
      return @client.read(1) if timeout.nil?
      ready = IO.select([@client], nil, nil, timeout)
      return :timeout unless ready
      @client.read(1)
    end

    # One byte of the line as an Integer, for binary protocols (ZMODEM):
    # telnet commands are taken out and a doubled IAC comes back as 255.
    # :timeout when nothing came within `timeout` seconds, nil on hangup.
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
        @after_cr = byte == 13
        next if after_cr && (byte == 10 || byte == 0)

        if byte == 13 || byte == 10
          write "\r\n"
          return line.force_encoding(Encoding::UTF_8).scrub('')
        end

        if byte == 8 || byte == 127
          unless line.empty?
            text = line.dup.force_encoding(Encoding::UTF_8)
            line = (text.valid_encoding? ? text.chop : text.byteslice(0, text.bytesize - 1)).b
            write "\b \b"
          end
          next
        end

        next if byte < 32 || line.bytesize >= MAX_LINE

        line << raw
        echo = if mask.nil? then raw
               elsif (byte & 0xc0) == 0x80 then ''
               else mask
               end
        write(echo)
      end
    end

    # True once the client has reported its window size (telnet NAWS). Real
    # terminals do; port scanners and password-guessing bots usually do not.
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

    # From here on the line speaks PETSCII to a Commodore 64 (see
    # BBS::Petscii): 40×25, lowercase character set, no mouse.
    def petscii!
      return if @petscii

      @mouse_enabled = false
      @term_cols     = Petscii::COLS
      @term_rows     = Petscii::ROWS
      send_raw Petscii.bytes("#{Petscii::LOWERCASE}#{Petscii::LOCK_CASE}#{Petscii::CLEAR}")
      @petscii = Petscii::Encoder.new
    end

    def petscii? = !@petscii.nil?

    # The caller's line itself, for a door that hands it on as it is
    # (BBS::Gateway).
    def line = @client

    # The caller's window size, as its NAWS reports it: clamped to sane
    # bounds, and left at 40×25 on a PETSCII line.
    def resize!(cols, rows)
      unless @petscii
        @term_cols = cols.clamp(20, MAX_COLS) if cols.positive?
        @term_rows = rows.clamp(8, MAX_ROWS) if rows.positive?
      end
      @naws_reported = true
    end

    def write(data)
      @client.write(@petscii ? @petscii.encode(data) : data)
    rescue StandardError
      nil
    end

    private

    # Reads a CSI / SS3 sequence after ESC. Returns a Symbol (key name),
    # a Symbol :"alt_<x>" (Alt-modified key), a MouseEvent, or :escape.
    def read_escape_sequence
      return :escape unless IO.select([@client], nil, nil, ESC_WAIT)

      b1 = @client.read(1)
      return :escape if b1.nil?

      case b1
      when '['
        read_csi
      when 'O'
        # SS3 — many terminals send F1-F4 this way
        b2 = @client.read(1)
        return :escape if b2.nil?
        case b2
        when 'A' then :up
        when 'B' then :down
        when 'C' then :right
        when 'D' then :left
        when 'P' then :f1
        when 'Q' then :f2
        when 'R' then :f3
        when 'S' then :f4
        when 'H' then :home
        when 'F' then :end
        else          :escape
        end
      when "\r"
        @after_cr = true
        :alt_enter
      else
        # Treat ESC + printable as Alt+<char>
        if b1.ord.between?(32, 126)
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
        if c.match?(/[A-Za-z~]/)
          final = c
          break
        end
        raw << c
        break if raw.length > 32 # safety
      end
      return :escape if final.nil?

      # X10 mouse report (no SGR 1006 support): ESC [ M b x y, each plus 32.
      if final == 'M' && raw.empty?
        b, x, y = 3.times.map { @client.read(1)&.ord.to_i - 32 }
        return decode_mouse(b, x, y, pressed: (b & 3) != 3)
      end

      # SGR mouse: ESC [ < b ; x ; y (M|m)
      if raw.start_with?('<') && (final == 'M' || final == 'm')
        parts = raw[1..].split(';')
        return :escape if parts.size != 3
        b = parts[0].to_i
        x = parts[1].to_i
        y = parts[2].to_i
        return decode_mouse(b, x, y, pressed: final == 'M')
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
      case final
      when 'A' then :up
      when 'B' then :down
      when 'C' then :right
      when 'D' then :left
      when 'H' then :home
      when 'F' then :end
      when 'Z' then :shift_tab
      when '~'
        case raw.to_i
        when 1, 7  then :home
        when 2     then :insert
        when 3     then :delete
        when 4, 8  then :end
        when 5     then :page_up
        when 6     then :page_down
        when 11    then :f1
        when 12    then :f2
        when 13    then :f3
        when 14    then :f4
        when 15    then :f5
        when 17    then :f6
        when 18    then :f7
        when 19    then :f8
        when 20    then :f9
        when 21    then :f10
        when 23    then :f11
        when 24    then :f12
        else            :escape
        end
      else :escape
      end
    end

    # The rest of a UTF-8 character whose first byte is `lead`; nil when
    # the bytes do not make one.
    def read_utf8(lead)
      bytes = lead.b
      (lead.ord >= 0xf0 ? 3 : lead.ord >= 0xe0 ? 2 : 1).times do
        return nil unless IO.select([@client], nil, nil, ESC_WAIT)

        nxt = @client.read(1)
        return nil if nxt.nil? || (nxt.ord & 0xc0) != 0x80

        bytes << nxt
      end
      char = bytes.force_encoding(Encoding::UTF_8)
      char.valid_encoding? ? char : nil
    end

    def decode_mouse(b, x, y, pressed:)
      mods = []
      mods << :shift if b & 4 != 0
      mods << :meta  if b & 8 != 0
      mods << :ctrl  if b & 16 != 0

      motion = (b & 32) != 0
      wheel  = (b & 64) != 0

      button_id = b & 3
      if wheel
        kind   = :wheel
        button = button_id == 0 ? :up : :down
      else
        button = case button_id
                 when 0 then :left
                 when 1 then :middle
                 when 2 then :right
                 else        :none
                 end
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
            buf << IAC if s.ord == IAC && buf.size < 64
          elsif buf.size < 64
            buf << b.ord
          end
        end
        if opt&.ord == NAWS_OPT && buf.size >= 4
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
        write "\r\n"
        return line.dup.force_encoding(Encoding::UTF_8).scrub('')
      when :backspace
        unless line.empty?
          line = line.dup.force_encoding(Encoding::UTF_8).chop.b
          write "\b \b"
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
