# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'time'

module BBS
  class Store
    attr_reader :headers, :path

    def initialize(path:, headers:)
      @path    = path
      @headers = headers
      @mutex   = Mutex.new
      @rows    = nil
    end

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

    def find(session_id)
      @mutex.synchronize do
        load_rows!
        row = @rows.find { |r| r['session_id'] == session_id }
        row ? row.to_h : nil
      end
    end

    def all
      @mutex.synchronize do
        load_rows!
        @rows.map(&:to_h)
      end
    end

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
    def clean(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8).scrub('').gsub(/[\u0000-\u0008\u000b-\u001f\u007f]/, '')
    end

    def ensure_file!
      FileUtils.mkdir_p(File.dirname(@path))
      return if File.exist?(@path)
      CSV.open(@path, 'w') { |csv| csv << @headers }
    end
  end
end
