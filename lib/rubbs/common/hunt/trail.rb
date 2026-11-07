# frozen_string_literal: true

require 'date'
require 'time'
require 'yaml'

module Rubbs
  module Common
    module Hunt
      # One hunt, read from its YAML file: the +slug+ (the year's folder and
      # the file's name, <tt>2026-w46-avian-route</tt>), the +title+, the
      # +intro+, its season from +opens+ to +closes+ (Times; by default the
      # Monday 00:00 to the next Monday 00:00 of the ISO week of the name, in
      # Hunt.time_zone), the +authors+ (names, not ranked) and its +steps+
      # (Step objects), and the +file+.
      #
      #   content/hunts/2026/w46-avian-route.yml   # the 46th week of 2026
      Trail = Data.define(:slug, :title, :intro, :opens, :closes, :authors, :steps, :file) do
        # The keys of a hunt's YAML.
        def self.keys = %w[title intro opens closes authors steps]

        # The hunt of the YAML file at +path+ and what is wrong with it,
        # <tt>[trail, problems]</tt>; the trail is +nil+ when the file cannot
        # be read as one.
        def self.read(path)
          data = YAML.safe_load_file(path, permitted_classes: [Date, Time])
          return [nil, ['not a mapping']] unless data.is_a?(Hash)

          build(path, data.to_h { |k, v| [k.to_s, v] })
        rescue Psych::Exception, SystemCallError => e
          [nil, ["cannot be read: #{e.message.lines.first.strip}"]]
        end

        # The slug of the file at +path+: its folder's name and its own.
        def self.slug_of(path) = "#{File.basename(File.dirname(path))}-#{File.basename(path, '.*')}"

        # The Monday 00:00 that opens the ISO week of the file at +path+ (a
        # Time), or +nil+ when the name does not tell a week.
        def self.week_of(path)
          year = File.basename(File.dirname(path))[/\A\d{4}\z/]
          week = File.basename(path)[/\Aw(\d{1,2})-/, 1]
          return nil unless year && week

          local(Date.commercial(year.to_i, week.to_i, 1).to_s)
        rescue Date::Error
          nil
        end

        # The Time of +text+ (<tt>2026-11-16 00:00</tt>, or a Date or Time)
        # taken as a time of Hunt.time_zone; +nil+ when it is no time.
        def self.local(text)
          return text if text.is_a?(Time)

          read = Time.parse(text.to_s)
          wall = Time.utc(read.year, read.month, read.day, read.hour, read.min, read.sec)
          (wall - Season.offset(Hunt.time_zone, wall)).utc
        rescue ArgumentError, TypeError
          nil
        end

        # The hunt made of +data+ (the YAML's mapping) read from +path+, and
        # what is wrong with it.
        def self.build(path, data)
          steps, problems = read_steps(data['steps'])
          opens, closes   = season_of(path, data)
          trail = new(
            slug:    slug_of(path),
            title:   data['title'].to_s.strip,
            intro:   data['intro'].to_s.strip,
            opens:   opens,
            closes:  closes,
            authors: Array(data['authors']).map(&:to_s),
            steps:   steps,
            file:    path
          )
          [trail, trail.shape_problems(data.keys - keys) + problems]
        end

        # When the hunt of +data+ at +path+ opens and closes: its +opens+ and
        # +closes+, by default the week of its name (#week_of) and a week on.
        def self.season_of(path, data)
          opens = data.key?('opens') ? local(data['opens']) : week_of(path)
          [opens, data.key?('closes') ? local(data['closes']) : opens && (opens + (7 * 86_400))]
        end

        # The steps of +list+ and their problems, each told with its number.
        def self.read_steps(list)
          return [[], ['no steps']] unless list.is_a?(Array) && !list.empty?

          list.each_with_index.with_object([[], []]) do |(hash, i), (steps, problems)|
            step, wrong = Step.read(hash)
            steps << step if step
            problems.concat(wrong.map { |p| "step #{i + 1}: #{p}" })
          end
        end

        # What is wrong with the hunt as a whole: no title, no season, and
        # the +unknown+ keys.
        def shape_problems(unknown = [])
          [*('no title' if title.empty?), *season_problems, *unknown.map { |k| "unknown key #{k}" }]
        end

        # What is wrong with the season: none, or it closes before it opens.
        def season_problems
          return ['no season: name it w<week>-<name>.yml in a year folder, or give opens and closes'] unless opens && closes

          closes <= opens ? ['it closes before it opens'] : []
        end

        # What is wrong with the parts of the steps, seen against +catalog+
        # (a Rubbs::Common::Badges::Catalog).
        def part_problems(catalog)
          steps.each_with_index.flat_map do |step, i|
            step.parts.flat_map { |part| part.problems(catalog).map { |p| "step #{i + 1}: #{p}" } }
          end
        end

        # Whether the hunt is in its season at +now+.
        def season?(now = Time.now) = !opens.nil? && opens <= now && now < closes

        # Whether its season is over at +now+ (it can still be played).
        def past?(now = Time.now) = !closes.nil? && closes <= now

        # The fragments of the steps before step +index+ (0-based).
        def fragments(index) = steps.first(index).filter_map(&:fragment)
      end
    end
  end
end
