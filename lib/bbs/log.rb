# frozen_string_literal: true

require 'json'
require 'time'

module BBS
  # The lines of BBS.log, written to stderr one at a time: as text for a
  # person (the default) or as JSON for a log pipeline
  # (<tt>BBS.config.log_format = :json</tt>, or <tt>BBS_LOG_FORMAT=json</tt>).
  #
  #   feedia-bbs: catalog refresh: SocketError: getaddrinfo failed retry_in=10
  #   {"time":"2026-11-04T10:12:03.402+01:00","level":"warn","board":"feedia-bbs",
  #    "tag":"catalog refresh","msg":"getaddrinfo failed","error":"SocketError","retry_in":10}
  #
  # A line written in a caller's thread carries the session's id
  # (+session+), so the lines of one call can be read together.
  module Log
    # The levels of a line, mildest first.
    LEVELS = %i[debug info warn error fatal].freeze
    # Lines of an error's backtrace a line carries.
    BACKTRACE_LINES = 5
    # The thread-local key of the current session's id.
    SESSION_KEY = :bbs_session_id

    @mutex = Mutex.new

    class << self
      # Writes one line: +tag+ (what it is about), +message+ (a String or an
      # exception), its +level+ (+:error+ for an exception, +:info+ for a
      # String unless given) and +fields+, more facts as keys and values.
      # Returns +nil+.
      def write(tag, message, level: nil, **fields)
        level ||= message.is_a?(Exception) ? :error : :info
        raise ArgumentError, "unknown log level #{level.inspect}" unless LEVELS.include?(level)

        line = BBS.config.log_format.to_s == 'json' ? json(tag, message, level, fields) : text(tag, message, level, fields)
        @mutex.synchronize { $stderr.write("#{line}\n") }
        nil
      end

      # Runs the block with +session_id+ as the session of the lines it
      # writes in this thread. Returns the block's value.
      def with_session(session_id)
        before = Thread.current[SESSION_KEY]
        Thread.current[SESSION_KEY] = session_id
        yield
      ensure
        Thread.current[SESSION_KEY] = before
      end

      # The id of the session whose thread this is, or +nil+.
      def session_id = Thread.current[SESSION_KEY]

      private

      def text(tag, message, level, fields)
        words = message.is_a?(Exception) ? "#{message.class}: #{message.message}" : message.to_s
        facts = fields.map { |key, value| " #{key}=#{value}" }.join
        line  = "#{BBS.config.log_tag}: #{tag}: #{words}#{facts}"
        return line unless message.is_a?(Exception) && %i[error fatal].include?(level)

        [line, *backtrace(message).map { |frame| "  #{frame}" }].join("\n")
      end

      def json(tag, message, level, fields)
        record = { time: Time.now.iso8601(3), level: level, board: BBS.config.log_tag, tag: tag.to_s }
        record.merge!(message.is_a?(Exception) ? error_facts(message, level) : { msg: message.to_s })
        record[:session] = session_id if session_id
        JSON.generate(record.merge(fields))
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
