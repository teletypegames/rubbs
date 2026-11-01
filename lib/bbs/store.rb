# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'time'

module BBS
  # A small thread-safe CSV table keyed by session id, for keeping what
  # callers entered. The file is created with a header row on first use and
  # read once into memory.
  #
  #   store = BBS::Store.new(path: 'data/callers.csv', headers: %w[session_id timestamp name])
  #   store.upsert(session_id: ctx[:session_id], name: 'Ada')
  #
  # A +session_id+ column is the key; a +timestamp+ column, when present, is
  # filled with the UTC time a row is created.
  class Store
    # The control characters removed from a value before it is written:
    # C0 except tab and LF, DEL, C1 and the bidirectional controls
    # (BBS::Text::CONTROLS).
    CONTROL_CHARS = Text::CONTROLS

    # The column names (an Array of String) and the CSV file path.
    attr_reader :headers, :path

    # Creates a store over the CSV file at +path+ with the column names
    # +headers+. The file is not touched until the first read or write.
    def initialize(path:, headers:)
      @path    = path
      @headers = headers
      @mutex   = Mutex.new
      @rows    = nil
    end

    # Updates the row of +session_id+ with +fields+, or appends a new row
    # when there is none. Keys that are not columns are ignored; values are
    # stored as strings with control characters removed. Writes the file.
    #
    # Returns +self+.
    def upsert(session_id:, **fields)
      @mutex.synchronize do
        load_rows!
        row = @rows.find { |r| r['session_id'] == session_id }

        if row
          fields.each { |k, v| row[k.to_s] = clean(v) if @headers.include?(k.to_s) }
          flush!
        else
          @rows << build_row(session_id, fields)
          append_row(@rows.last)
        end
      end
      self
    end

    # Returns the row of +session_id+ as a Hash of column name to value, or
    # +nil+.
    def find(session_id)
      @mutex.synchronize do
        load_rows!
        row = @rows.find { |r| r['session_id'] == session_id }
        row ? row.to_h : nil
      end
    end

    # Returns every row as an Array of Hash.
    def all
      @mutex.synchronize do
        load_rows!
        @rows.map(&:to_h)
      end
    end

    # Removes the row of +session_id+ and rewrites the file when there was
    # one.
    def delete(session_id)
      @mutex.synchronize do
        load_rows!
        removed = @rows.reject! { |r| r['session_id'] == session_id }
        flush! if removed
      end
    end

    private

    def load_rows!
      return @rows if @rows
      ensure_file!
      # Bytes, not text: a line with invalid UTF-8 (e.g. raw telnet negotiation saved with the input)
      # would otherwise raise CSV::InvalidEncodingError and kill every session that touches the store.
      raw   = File.binread(@path).force_encoding(Encoding::UTF_8).scrub
      table = CSV.parse(raw, headers: true)
      @rows = table.map { |row| row }
    end

    def build_row(session_id, fields)
      values = @headers.map do |h|
        case h
        when 'session_id' then session_id
        when 'timestamp'  then Time.now.utc.iso8601
        else (v = fields[h.to_sym]).nil? ? nil : clean(v)
        end
      end
      CSV::Row.new(@headers, values)
    end

    def append_row(row)
      CSV.open(@path, 'a') { |csv| csv << row.fields }
    end

    def flush!
      CSV.open(@path, 'w') do |csv|
        csv << @headers
        @rows.each { |r| csv << r.fields }
      end
    end

    # Valid UTF-8 without control characters, so a stray byte from the terminal never lands in the file.
    def clean(value) = Text.clean(value)

    def ensure_file!
      FileUtils.mkdir_p(File.dirname(@path))
      return if File.exist?(@path)
      CSV.open(@path, 'w') { |csv| csv << @headers }
    end
  end
end
