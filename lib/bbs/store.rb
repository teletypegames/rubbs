# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'time'

module BBS
  class Store
    def initialize(path:, headers:)
      @path    = path
      @headers = headers
      @mutex   = Mutex.new
    end

    def upsert(session_id:, **fields)
      @mutex.synchronize do
        ensure_file!
        rows = CSV.read(@path, headers: true)
        row  = rows.find { |r| r['session_id'] == session_id }

        if row
          fields.each { |k, v| row[k.to_s] = v }
        else
          values = @headers.map do |h|
            case h
            when 'session_id' then session_id
            when 'timestamp'  then Time.now.utc.iso8601
            else fields[h.to_sym]
            end
          end
          rows << CSV::Row.new(@headers, values)
        end

        CSV.open(@path, 'w') do |csv|
          csv << @headers
          rows.each { |r| csv << r.fields }
        end
      end
    end

    private

    def ensure_file!
      FileUtils.mkdir_p(File.dirname(@path))
      return if File.exist?(@path)
      CSV.open(@path, 'w') { |csv| csv << @headers }
    end
  end
end
