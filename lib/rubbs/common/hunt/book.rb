# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # The hunts of a folder (<tt><dir>/<year>/*.yml</tt>, any depth), read
      # again when a file is added, changed or removed: the board looks at
      # most every +every+ seconds, so a deploy of a new hunt needs no
      # restart. A file that cannot be read as a Trail is left out (and
      # logged); #problems tells why.
      class Book
        # The folder (+nil+ for none).
        attr_reader :dir

        # A book of +dir+, looked at again at most every +every+ seconds.
        def initialize(dir, every: 60)
          @dir     = dir
          @every   = every
          @mutex   = Mutex.new
          @trails  = {}
          @checked = nil
          @stamp   = nil
        end

        # The hunt files, sorted.
        def files = dir && File.directory?(dir) ? Dir.glob('**/*.{yml,yaml}', base: dir).sort.map { |f| File.join(dir, f) } : []

        # Every hunt that could be read, by slug, oldest season first.
        def trails
          refresh
          @trails
        end

        # The hunt of +slug+, or +nil+.
        def [](slug) = trails[slug.to_s]

        # The hunt in its season at +now+, or +nil+ (the first, when two
        # meet: #problems tells of that).
        def in_season(now = Time.now) = trails.values.find { |t| t.season?(now) }

        # The hunts whose season is over at +now+, the latest first.
        def past(now = Time.now) = trails.values.select { |t| t.past?(now) }.sort_by(&:opens).reverse

        # What is wrong with the files, "<file>: <problem>" Strings (empty
        # when nothing is): their own problems, the parts' against +catalog+
        # (a Rubbs::Common::Badges::Catalog) and seasons that meet.
        def problems(catalog = Badges.catalog)
          read = files.map { |path| [path, *Trail.read(path)] }
          own  = read.flat_map { |path, trail, wrong| file_problems(path, trail, wrong, catalog) }
          own + overlaps(read.map { |_, trail, _| trail }.select { |t| t&.opens && t.closes })
        end

        # Reads the files again now (whatever #every says). Returns +self+.
        def reload!
          @mutex.synchronize { load(stamp) }
          self
        end

        private

        def refresh
          return if @checked && Time.now - @checked < @every

          @mutex.synchronize do
            @checked = Time.now
            now = stamp
            load(now) unless now == @stamp
          end
        end

        def stamp = files.map { |f| [f, File.mtime(f).to_f] }

        def load(stamp)
          @stamp  = stamp
          @trails = stamp.filter_map { |path, _| usable(path) }.sort_by { |t| t.opens || Time.at(0) }.to_h { |t| [t.slug, t] }
        end

        def usable(path)
          trail, problems = Trail.read(path)
          return trail if trail && problems.empty?

          Rubbs.log('hunt', "#{File.basename(path)} is left out", problems: problems)
          nil
        end

        def file_problems(path, trail, wrong, catalog)
          (wrong + (trail ? trail.part_problems(catalog) : [])).map { |p| "#{File.basename(path)}: #{p}" }
        end

        def overlaps(trails)
          trails.sort_by(&:opens).each_cons(2).filter_map do |a, b|
            "#{File.basename(b.file)}: its season meets the season of #{File.basename(a.file)}" if b.opens < a.closes
          end
        end
      end
    end
  end
end
