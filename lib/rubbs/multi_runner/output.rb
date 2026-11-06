# frozen_string_literal: true

require 'json'
require 'time'

module Rubbs
  class MultiRunner
    # The supervisor's stderr, written by every board's process through a
    # pipe, one line at a time. A board's JSON log record goes out as it is;
    # any other line (a Ruby warning, a crash's backtrace) is wrapped in a
    # record with the board's name (+board+), tag +output+, level +warn+, so
    # that every line says whose it is. In the text log format (BBS_LOG_FORMAT)
    # the line is prefixed with the name instead.
    class Output
      # The start of the line a board's process writes first, before its
      # name (Child): read here, never written out.
      NAME_LINE = "\x1Erubbs-board "

      # [io] where the lines go (default: <tt>$stderr</tt>)
      def initialize(io = $stderr)
        @io = io
        @mu = Mutex.new
      end

      # Reads +reader+ to its end in a thread of its own, writing each line
      # for +child+ (a Child: its +name+, and the +slug+ it learns from the
      # first JSON record). Returns the Thread.
      def pump(reader, child)
        Thread.new do
          reader.each_line { |line| write(line, child) }
        rescue IOError
          nil
        ensure
          reader.close rescue nil
        end
      end

      # Writes one +line+ of +child+'s. Returns +nil+.
      def write(line, child)
        line = line.chomp
        return if line.empty?

        if line.start_with?(NAME_LINE)
          child.slug = line.delete_prefix(NAME_LINE)
          return nil
        end

        record = parse(line)
        child.slug ||= record['board'] if record&.dig('board')
        emit(record ? line : wrap(line, child))
      end

      # Writes +line+ as it is. Returns +nil+.
      def emit(line)
        @mu.synchronize { @io.write("#{line}\n") }
        nil
      end

      private

      def parse(line)
        return nil unless line.start_with?('{')

        record = JSON.parse(line)
        record.is_a?(Hash) ? record : nil
      rescue JSON::ParserError
        nil
      end

      def wrap(line, child)
        board = child.slug || child.name
        return "#{board}: #{line}" unless Rubbs.config.log_format.to_s == 'json'

        JSON.generate(time: Time.now.iso8601(3), level: :warn, board: board, tag: 'output', msg: line)
      end
    end
  end
end
