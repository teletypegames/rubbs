# frozen_string_literal: true

module Rubbs
  module Common
    module Files
      # A file sent down the line by the protocol the caller's terminal
      # receives with (Rubbs::Common::Files::Zmodem, Rubbs::Common::Files::Xmodem), and what to tell the caller
      # before and after. XMODEM carries no file name, so the terminal asks for
      # one: #start says which. A file comes up the line by XMODEM (::receive,
      # with ::upload_start and ::upload_result to tell the caller).
      #
      #   protocol = :zmodem
      #   screen.say(Rubbs::Common::Files::Transfer.start(protocol, 'GAME.PRG', data.bytesize))
      #   result = Rubbs::Common::Files::Transfer.send(session, protocol, 'GAME.PRG', data)
      #   screen.say(Rubbs::Common::Files::Transfer.result(result, protocol, 'GAME.PRG'))
      module Transfer
        # The protocols and their names.
        PROTOCOLS = { zmodem: 'ZMODEM', xmodem_1k: 'XMODEM-1K', xmodem: 'XMODEM' }.freeze

        # The name of +protocol+.
        def self.label(protocol) = PROTOCOLS.fetch(protocol)

        # Sends +data+ as the file +name+ on +session+ by +protocol+. Returns
        # +:ok+, +:cancelled+ or +:timeout+; raises Rubbs::Common::Line::Hangup when the line
        # drops. Writes a +transfer+ line of how it went.
        def self.send(session, protocol, name, data)
          result = case protocol
                   when :zmodem    then Zmodem.send_files(session, [[name, data]])
                   when :xmodem_1k then Xmodem.send_file(session, data, one_k: true)
                   else Xmodem.send_file(session, data)
                   end
          transferred(result, protocol, name, data)
          raise Line::Hangup if result == :hangup

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
          Rubbs.log(
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

        # The message of the +transfer+ line of an upload (::receive) by its
        # result; the bytes are +received+, any other (the line hung up) is
        # +dropped+.
        UPLOAD_OUTCOMES = {
          cancelled: 'upload cancelled',
          timeout:   'upload timeout',
          too_large: 'upload too large',
          failed:    'upload failed'
        }.freeze

        # Receives a file the caller uploads by XMODEM (checksum, CRC-16 or
        # 1K blocks, as the terminal sends) on +session+, at most +max_bytes+
        # bytes, waiting +wait+ seconds for the terminal to start (see
        # Rubbs::Common::Files::Xmodem.receive_file). Returns the bytes (the
        # padding of the last block included), or +:cancelled+, +:timeout+,
        # +:too_large+ or +:failed+; raises Rubbs::Common::Line::Hangup when
        # the line drops. Writes a +transfer+ line of how it went.
        def self.receive(session, max_bytes:, wait: Xmodem::WAIT)
          result = Xmodem.receive_file(session, max_bytes: max_bytes, wait: wait)
          received(result)
          raise Line::Hangup if result == :hangup

          result
        end

        # The +transfer+ line of an upload: +received+ with its +bytes+, or
        # how it failed.
        def self.received(result)
          return Rubbs.log('transfer', 'received', bytes: result.bytesize, protocol: 'xmodem') if result.is_a?(String)

          Rubbs.log('transfer', UPLOAD_OUTCOMES.fetch(result, 'upload dropped'), level: :warn, protocol: 'xmodem')
        end
        private_class_method :received

        # What to tell the caller before an XMODEM upload of +what+ (the kind
        # of file the board wants, e.g. <tt>'your .tcv picture'</tt>).
        def self.upload_start(what)
          "Start an XMODEM upload of #{what} in your terminal now (XMODEM, XMODEM-CRC or XMODEM-1K). " \
            'The board waits a minute for it; Esc or RUN/STOP gives up.'
        end

        # What to tell the caller after an upload that ended with +result+ (a
        # Symbol of ::receive); +nil+ for the bytes of a finished upload, which
        # the board judges itself.
        def self.upload_result(result)
          case result
          when String then nil
          when :cancelled then 'The upload was cancelled.'
          when :timeout then 'Your terminal did not send the file by XMODEM in time.'
          when :too_large then 'The file is too large for the board.'
          when :failed then 'The upload kept failing: the blocks came broken or out of order.'
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
  end
end
