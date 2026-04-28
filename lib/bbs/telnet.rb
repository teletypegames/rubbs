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

    def negotiate
      send_raw [IAC, WILL, SGA_OPT].pack('C*')
      send_raw [IAC, WILL, ECHO_OPT].pack('C*')
      send_raw [IAC, DO,   SGA_OPT].pack('C*')
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

    def absorb_iac
      cmd = @client.read(1)
      return if cmd.nil?

      case cmd.ord
      when SB
        loop do
          b = @client.read(1)
          break if b.nil?
          if b.ord == IAC
            s = @client.read(1)
            break if s.nil? || s.ord == SE
          end
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
