# frozen_string_literal: true

require 'csv'

module Rubbs
  module Common
    module Storage
      class Store
        # The rows of a Store's CSV file of earlier versions, read once for the
        # import into SQLite. A broken row does not stop the import: a record
        # that is not CSV (an unclosed quote runs until a line that is a whole row, at most
        # MAX_LINES lines), has
        # more fields than the header or no +session_id+ is skipped, and its
        # lines are set aside in <tt><path>.rejected</tt>, under the header,
        # for a sysop to look at.
        #
        #   csv = Rubbs::Common::Storage::Store::CsvImport.new('data/callers.csv', %w[session_id name])
        #   csv.rows                          # => [{ 'session_id' => 'a', 'name' => 'Ada' }, ...]
        #   csv.finish('data/callers.sqlite3') # renames the file, writes the rejects
        class CsvImport
          # The most lines a quoted field may run over before its record counts
          # as broken.
          MAX_LINES = 50

          # Reads the CSV file at +path+ (as bytes: invalid UTF-8 is dropped,
          # not fatal), keeping the +columns+ (Array of String) of each row.
          def initialize(path, columns)
            @path     = path
            @columns  = columns
            @rows     = []
            @rejected = []
            read
          end

          # The good rows, each a Hash of column name => String or +nil+.
          attr_reader :rows

          # The broken records, each the lines it was read from.
          attr_reader :rejected

          # Renames the CSV file to <tt><path>.imported</tt>, writes the rejected
          # records to <tt><path>.rejected</tt> when there are any, and returns
          # a line for the log naming +database+, where the rows went.
          def finish(database)
            File.rename(@path, "#{@path}.imported")
            File.write("#{@path}.rejected", @header + @rejected.join) if @rejected.any?
            "#{@rows.size} rows of #{@path} imported into #{database}" +
              (@rejected.any? ? ", #{@rejected.size} set aside in #{@path}.rejected" : '')
          end

          private

          def read
            lines   = Text.utf8(File.binread(@path)).lines
            @header = lines.shift.to_s
            names   = parse(@header)
            return @rejected.concat(lines) unless names.is_a?(Array)

            records(lines, names.size) { |text, fields| keep(text, fields, names) }
          end

          # Yields each record's text and fields (an Array, or a Symbol when it
          # is not CSV). A record left open by a stray quote ends where a line
          # that is a whole row of +width+ fields by itself begins.
          def records(lines, width, &)
            open = lines.inject(+'') { |text, line| take(text, line, width, &) }
            yield open, :broken unless open.empty?
          end

          # Adds +line+ to the +open+ record, yields the records that ends, and
          # returns what stays open.
          def take(open, line, width)
            if !open.empty? && whole?(line, width)
              yield open, :broken
              open = +''
            end
            open += line
            fields = parse(open)
            return open if fields == :open && open.count("\n") < MAX_LINES

            yield open, fields
            +''
          end

          def whole?(line, width) = parse(line).then { |fields| fields.is_a?(Array) && fields.size == width }

          def keep(text, fields, names)
            return if fields.is_a?(Array) && fields.empty?
            return @rejected << text unless fields.is_a?(Array) && fields.size <= names.size

            row = names.zip(fields).to_h.slice(*@columns)
            row[@columns.first].to_s.empty? ? @rejected << text : @rows << row
          end

          # The fields of +text+; +:open+ while a quoted field is still open,
          # +:broken+ when it is no CSV.
          def parse(text)
            CSV.parse_line(text) || []
          rescue CSV::MalformedCSVError
            text.count('"').odd? ? :open : :broken
          end
        end
      end
    end
  end
end
