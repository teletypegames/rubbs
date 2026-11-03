# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'zlib'

module BBS
  # A catalog kept as one gzipped JSON file and held in memory whole: the
  # seed that ships with the board, the fresher copy a refresh writes into
  # +data/+, whichever is newer read at start, and a new one swapped in at
  # once when a refresh lands. The block turns the records (a Hash) into
  # what the board reads.
  #
  #   CATALOG = BBS::Snapshot.new(seed: 'config/catalog.json.gz', path: 'data/catalog.json.gz',
  #                               source: 'Wikidata (CC0 1.0)') do |records|
  #     records['series'].map { |r| SeriesModel.from_record(r) }
  #   end
  #   CATALOG.value          # what the block made of the newest records
  #   CATALOG.generated_at   # when those were fetched
  #   CATALOG.replace(fresh_records)
  #
  # Refreshing on a schedule: #refresh_every.
  class Snapshot
    # The time of a snapshot that was never read.
    NEVER = Time.at(0).utc

    # When the records in memory were fetched (NEVER when none were read).
    attr_reader :generated_at

    # [seed]   the file shipped with the board
    # [path]   the file a refresh writes
    # [source] where the records are from, written into the file
    # [meta]   more keys written into the file (a licence)
    # [build]  the block making the value from the records
    #
    # Reads the newer of the two files; a file that cannot be read is
    # logged and passed over; with neither, the value is the block's of an
    # empty Hash.
    def initialize(seed:, path:, source: nil, meta: {}, &build)
      @seed   = seed
      @path   = path
      @source = source
      @meta   = meta
      @build  = build || ->(records) { records }
      @lock   = Mutex.new
      @value, @generated_at = [read(@path), read(@seed)].compact.max_by(&:last) || [@build.call({}), NEVER]
    end

    # The value made from the newest records.
    def value = @lock.synchronize { @value }

    # The age of the records in seconds.
    def age = Time.now - @generated_at

    # Writes +records+ (a Hash) as the new file at +path+ and swaps their
    # value in. Raises (SystemCallError, IOError) when the file could not be
    # written; the old value stays. Returns the new value.
    def replace(records, at: Time.now.utc)
      self.class.write(@path, @meta.merge(records), at, source: @source)
      fresh = @build.call(records)
      @lock.synchronize do
        @value = fresh
        @generated_at = at
      end
      fresh
    end

    # Checks every +every+ seconds in the background (BBS.background) and,
    # when the records are older than +ttl+, fetches new ones with the block
    # and #replace s them. A block that answers +nil+ or raises leaves the
    # old ones (the error is logged). Returns the Thread.
    def refresh_every(every, ttl:, name: 'snapshot refresh', &fetch)
      BBS.background(name, every: every) { refresh_if_older(ttl, &fetch) }
    end

    # Fetches and replaces the records when they are older than +ttl+
    # seconds. Returns +:fresh+, +:ok+, or raises what the block raises.
    def refresh_if_older(ttl)
      return :fresh if age < ttl

      records = yield
      raise ArgumentError, 'the refresh gave no records' if records.nil? || records.empty?

      replace(records)
      :ok
    end

    # Writes +records+ to +path+ atomically as gzipped JSON with +source+
    # and the time +at+ (a seed is written this way by a board's tool).
    def self.write(path, records, at, source: nil)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp"
      Zlib::GzipWriter.open(tmp, Zlib::BEST_COMPRESSION) do |gz|
        gz.write(JSON.generate({ 'source' => source, 'generated' => at.utc.iso8601, **records }.compact))
      end
      File.rename(tmp, path)
    end

    private

    def read(path)
      return nil unless path && File.exist?(path)

      data = JSON.parse(Zlib::GzipReader.open(path, &:read))
      [@build.call(data), Time.iso8601(data.fetch('generated'))]
    rescue StandardError => e
      BBS.log('snapshot', "reading #{path}: #{e.class}: #{e.message}")
      nil
    end
  end
end
