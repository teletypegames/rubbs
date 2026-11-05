# frozen_string_literal: true

require 'json'
require 'time'

module Rubbs
  module Common
    # The lines of Rubbs.log, written to stderr one at a time: as text for a
    # person (the default) or as JSON for a log pipeline
    # (<tt>Rubbs.config.log_format = :json</tt>, or <tt>BBS_LOG_FORMAT=json</tt>).
    #
    #   feedia-bbs: catalog refresh: SocketError: getaddrinfo failed retry_in=10
    #   {"time":"2026-11-04T10:12:03.402+01:00","level":"warn","board":"feedia-bbs",
    #    "tag":"catalog refresh","msg":"getaddrinfo failed","error":"SocketError","retry_in":10}
    #
    # A line written in a caller's thread carries the session's id
    # (+session+), so the lines of one call can be read together, and the
    # caller's IP address (+ip+: the forwarded one of a call through another
    # board or bbs-web, see Telnet::Forwarded#caller_ip), so a log pipeline can
    # count callers and tell where they come from.
    module Log
      # The levels of a line, mildest first.
      LEVELS = %i[debug info warn error fatal].freeze
      # Lines of an error's backtrace a line carries.
      BACKTRACE_LINES = 5
      # The thread-local key of the current session's id.
      SESSION_KEY = :bbs_session_id
      # An ANSI escape sequence (a colour of a label), left out of a +use+
      # line's name.
      ANSI_CODE = /\e\[[0-9;?]*[A-Za-z]/
      # The longest name of a +use+ line (Log.use), in characters.
      USE_NAME = 40
      # The thread-local key of the current session (for its caller's IP).
      CALLER_KEY = :bbs_session
      # Lines ::recent keeps.
      RECENT = 500

      # A line as ::recent keeps it: its +time+ (a Time), +level+ (a Symbol),
      # +tag+, +message+ (the words; an exception's class and message) and
      # +fields+ (a Hash, with +session+ and +ip+ when written in a call).
      Entry = Data.define(:time, :level, :tag, :message, :fields)

      @mutex  = Mutex.new
      @recent = []

      class << self
        # Writes one line: +tag+ (what it is about), +message+ (a String or an
        # exception), its +level+ (+:error+ for an exception, +:info+ for a
        # String unless given) and +fields+, more facts as keys and values.
        # Returns +nil+.
        def write(tag, message, level: nil, **fields)
          level ||= message.is_a?(Exception) ? :error : :info
          raise ArgumentError, "unknown log level #{level.inspect}" unless LEVELS.include?(level)

          line  = Rubbs.config.log_format.to_s == 'json' ? json(tag, message, level, fields) : text(tag, message, level, fields)
          entry = entry(tag, message, level, fields)
          @mutex.synchronize do
            $stderr.write("#{line}\n")
            @recent << entry
            @recent.shift while @recent.size > RECENT
          end
          nil
        end

        # The last lines written in this process (at most RECENT, or +limit+),
        # the oldest first, as Entry values: a sysop's screen reads the log
        # without the server's shell.
        def recent(limit = RECENT) = @mutex.synchronize { @recent.last(limit) }

        # Runs the block with +session_id+ as the session of the lines it
        # writes in this thread. With +caller+ (the Rubbs::Common::Line::Session, or anything
        # with a +caller_ip+), each line also carries the caller's IP address
        # as +ip+, asked for when the line is written (the address a gateway
        # forwards comes in after the call does). Returns the block's value.
        def with_session(session_id, caller: nil)
          before = [Thread.current[SESSION_KEY], Thread.current[CALLER_KEY]]
          Thread.current[SESSION_KEY] = session_id
          Thread.current[CALLER_KEY]  = caller
          yield
        ensure
          Thread.current[SESSION_KEY], Thread.current[CALLER_KEY] = before
        end

        # The id of the session whose thread this is, or +nil+.
        def session_id = Thread.current[SESSION_KEY]

        # Writes the +use+ line of a section the caller opened: +name+ (a
        # command's name, or a menu item's label, see ::use_name), its +kind+
        # (+:command+ for a Rubbs::Modern::Application command, +:menu+ for an item of a
        # PETSCII menu) and the +face+ (+:modern+ or +:petscii+). Returns +nil+.
        #
        #   {"tag":"use","msg":"feeds","face":"modern","kind":"command",…}
        def use(name, kind:, face:)
          name = use_name(name)
          return nil if name.empty?

          caller = Thread.current[CALLER_KEY]
          caller.place = name if caller.respond_to?(:place=)

          write('use', name, face: face.to_s, kind: kind.to_s)
        end

        # +label+ as the name of a +use+ line: without colour codes and
        # hotkey marks, lower case, only letters, digits and single spaces, at
        # most USE_NAME characters.
        def use_name(label)
          plain = label.to_s.gsub(ANSI_CODE, '').downcase.gsub(/[^[:alnum:]]+/, ' ').strip
          plain[0, USE_NAME].to_s.strip
        end

        # The IP address of the caller whose thread this is, as a String, or
        # +nil+ (no call, or a line without an address).
        def caller_ip
          caller = Thread.current[CALLER_KEY] or return nil
          caller.caller_ip&.to_s
        rescue StandardError
          nil
        end

        private

        def text(tag, message, level, fields)
          words = message.is_a?(Exception) ? "#{message.class}: #{message.message}" : message.to_s
          facts = call_facts.merge(fields).map { |key, value| " #{key}=#{value}" }.join
          line  = "#{Rubbs.config.log_tag}: #{tag}: #{words}#{facts}"
          return line unless message.is_a?(Exception) && %i[error fatal].include?(level)

          [line, *backtrace(message).map { |frame| "  #{frame}" }].join("\n")
        end

        def json(tag, message, level, fields)
          record = { time: Time.now.iso8601(3), level: level, board: Rubbs.config.log_tag, tag: tag.to_s }
          record.merge!(message.is_a?(Exception) ? error_facts(message, level) : { msg: message.to_s })
          record[:session] = session_id if session_id
          JSON.generate(record.merge(call_facts, fields))
        end

        def entry(tag, message, level, fields)
          words = message.is_a?(Exception) ? "#{message.class}: #{message.message}" : message.to_s
          facts = { session: session_id }.compact.merge(call_facts, fields)
          Entry.new(time: Time.now, level: level, tag: tag.to_s, message: words, fields: facts)
        end

        # The +ip+ of the caller of this thread, when there is one.
        def call_facts
          ip = caller_ip
          ip ? { ip: ip } : {}
        end

        def error_facts(error, level)
          facts = { msg: error.message, error: error.class.name }
          facts[:backtrace] = backtrace(error) if %i[error fatal].include?(level)
          facts
        end

        def backtrace(error) = Array(error.backtrace).first(BACKTRACE_LINES)
      end
    end
  end
end
