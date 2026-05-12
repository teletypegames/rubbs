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
      return if @mouse_enabled
      write "\e[?1000h\e[?1006h"
      @mouse_enabled = true
    end

    def disable_mouse
      return unless @mouse_enabled
      write "\e[?1006l\e[?1000l"
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

        case byte
        when 13, 10  then return :enter
        when 9       then return :tab
        when 27      then return read_escape_sequence
        when 8, 127  then return :backspace
        when 3       then return :interrupt
        when 1..26   then return :"ctrl_#{(byte + 96).chr}"
        when 32..126 then return raw
        end
      end
    end

    def read_byte(timeout = nil)
      return @client.read(1) if timeout.nil?
      ready = IO.select([@client], nil, nil, timeout)
      return :timeout unless ready
      @client.read(1)
    end

    def readline
      line    = +""
      last_cr = false

      loop do
        raw  = @client.read(1)
        return nil if raw.nil?
        byte = raw.ord

        if byte == IAC
          absorb_iac
          last_cr = false
          next
        end

        if byte == 13
          last_cr = true
          next
        end

        if byte == 10 || (byte == 0 && last_cr)
          write "\r\n"
          return line
        end

        last_cr = false
        next if byte == 0

        if byte == 8 || byte == 127
          unless line.empty?
            line.chop!
            write "\b \b"
          end
          next
        end

        next if byte < 32

        line << raw
        write raw
      end
    end

    def write(data)
      @client.write(data)
    rescue StandardError
      nil
    end

    private

    # Reads a CSI / SS3 sequence after ESC. Returns a Symbol (key name),
    # a Symbol :"alt_<x>" (Alt-modified key), a MouseEvent, or :escape.
    def read_escape_sequence
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
        when 'P' then :f1
        when 'Q' then :f2
        when 'R' then :f3
        when 'S' then :f4
        when 'H' then :home
        when 'F' then :end
        else          :escape
        end
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

      # SGR mouse: ESC [ < b ; x ; y (M|m)
      if raw.start_with?('<') && (final == 'M' || final == 'm')
        parts = raw[1..].split(';')
        return :escape if parts.size != 3
        b = parts[0].to_i
        x = parts[1].to_i
        y = parts[2].to_i
        return decode_mouse(b, x, y, pressed: final == 'M')
      end

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

    def absorb_iac
      cmd = @client.read(1)
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
          else
            buf << b.ord
          end
        end
        if opt&.ord == NAWS_OPT && buf.size >= 4
          cols = (buf[0] << 8) | buf[1]
          rows = (buf[2] << 8) | buf[3]
          @term_cols = cols if cols > 0
          @term_rows = rows if rows > 0
        end
      when WILL, WONT, DO, DONT
        @client.read(1)
      end
    end

    def send_raw(data)
      @client.write(data)
    rescue StandardError
      nil
    end
  end
end
