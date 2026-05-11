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

    def negotiate
      @term_cols = 80
      @term_rows = 24
      send_raw [IAC, WILL, SGA_OPT].pack('C*')
      send_raw [IAC, WILL, ECHO_OPT].pack('C*')
      send_raw [IAC, DO,   SGA_OPT].pack('C*')
      send_raw [IAC, DO,   NAWS_OPT].pack('C*')
    end

    def readkey
      loop do
        raw  = @client.read(1)
        return nil if raw.nil?
        byte = raw.ord

        if byte == IAC
          absorb_iac
          next
        end

        case byte
        when 13, 10  then return :enter
        when 27      then return read_escape_sequence
        when 8, 127  then return :backspace
        when 3       then return :interrupt
        when 32..126 then return raw
        end
      end
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

    def read_escape_sequence
      b1 = @client.read(1)
      return :escape if b1.nil? || b1 != '['

      b2 = @client.read(1)
      return :escape if b2.nil?

      case b2
      when 'A' then :up
      when 'B' then :down
      when 'C' then :right
      when 'D' then :left
      else          :escape
      end
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
