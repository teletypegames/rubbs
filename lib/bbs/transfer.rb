# frozen_string_literal: true

module BBS
  # A file sent down the line by the protocol the caller's terminal
  # receives with (BBS::Zmodem, BBS::Xmodem), and what to tell the caller
  # before and after. XMODEM carries no file name, so the terminal asks for
  # one: #start says which.
  #
  #   protocol = :zmodem
  #   screen.say(BBS::Transfer.start(protocol, 'GAME.PRG', data.bytesize))
  #   result = BBS::Transfer.send(session, protocol, 'GAME.PRG', data)
  #   screen.say(BBS::Transfer.result(result, protocol, 'GAME.PRG'))
  module Transfer
    # The protocols and their names.
    PROTOCOLS = { zmodem: 'ZMODEM', xmodem_1k: 'XMODEM-1K', xmodem: 'XMODEM' }.freeze

    # The name of +protocol+.
    def self.label(protocol) = PROTOCOLS.fetch(protocol)

    # Sends +data+ as the file +name+ on +session+ by +protocol+. Returns
    # +:ok+, +:cancelled+ or +:timeout+; raises BBS::Hangup when the line
    # drops. Writes a +transfer+ line of how it went.
    def self.send(session, protocol, name, data)
      result = case protocol
               when :zmodem    then Zmodem.send_files(session, [[name, data]])
               when :xmodem_1k then Xmodem.send_file(session, data, one_k: true)
               else Xmodem.send_file(session, data)
               end
      transferred(result, protocol, name, data)
      raise Hangup if result == :hangup

      result
    end

    # The message of the +transfer+ line (::send) by the result of a
    # download; any other (the line hung up) is +dropped+.
    OUTCOMES = { ok: 'sent', cancelled: 'cancelled', timeout: 'timeout' }.freeze

    # The +transfer+ line of a download: +sent+, +cancelled+, +timeout+ or
    # +dropped+, with the +file+'s name, its +bytes+ and the +protocol+
    # (+zmodem+, +xmodem_1k+, +xmodem+).
    def self.transferred(result, protocol, name, data)
      outcome = OUTCOMES.fetch(result, 'dropped')
      BBS.log(
        'transfer',
        outcome,
        level:    outcome == 'sent' ? :info : :warn,
        file:     name.to_s,
        bytes:    data.to_s.bytesize,
        protocol: protocol.to_s
      )
    end
    private_class_method :transferred

    # What to tell the caller before the transfer of +name+ (+size+ bytes),
    # and, for XMODEM, the name to save it as (+save_as+, default +name+).
    def self.start(protocol, name, size, save_as: name)
      if protocol == :zmodem
        "Sending #{name} (#{size} bytes) by ZMODEM. Most terminals start the download by themselves; Esc gives up."
      else
        "Start an #{label(protocol)} download in your terminal now and save it as #{save_as}. " \
          'The board waits a minute for it; Esc or RUN/STOP gives up.'
      end
    end

    # What to tell the caller after the transfer of +name+ ended with
    # +result+.
    def self.result(result, protocol, name)
      case result
      when :ok then ok(protocol, name)
      when :cancelled then 'The download was cancelled.'
      when :timeout then "Your terminal did not take the file by #{label(protocol)} in time."
      else 'The line dropped.'
      end
    end

    def self.ok(protocol, name)
      return "#{name} went over, byte for byte." if protocol == :zmodem

      "#{name} went over. #{label(protocol)} fills its last block up, so the file can be longer by up to " \
        "#{protocol == :xmodem_1k ? 1023 : 127} bytes; a Commodore loads it all the same."
    end
    private_class_method :ok
  end
end
