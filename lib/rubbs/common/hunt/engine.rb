# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # Who is where in which hunt, on the Central's database (MIGRATIONS):
      # a mark for every part an account reached (+opened_at+) and solved
      # (+done_at+), the hints it saw, its answers, and its finishes. The
      # open mark (no +done_at+) is where the account is now.
      class Engine
        # Where an account is in a hunt: the step and part (0-based) and when
        # it opened.
        Mark = Data.define(:hunt, :step, :part, :opened_at)

        # An engine on +db+ (a Sequel::Database migrated by MIGRATIONS).
        def initialize(db)
          @db = db
        end

        # Opens the first part of +trail+ (a Trail) for +account+ at +at+
        # (epoch seconds), unless it has begun it. Returns +self+.
        def start(account, trail, at)
          if marks(account, trail.slug).empty?
            @db[:hunt_marks].insert(account_id: account, hunt: trail.slug, step: 0, part: 0, opened_at: at)
          end
          self
        end

        # The open Mark of +account+ in the hunt +slug+, or +nil+.
        def current(account, slug)
          row = marks(account, slug).where(done_at: nil).first
          row && Mark.new(hunt: slug, step: row[:step], part: row[:part], opened_at: row[:opened_at])
        end

        # Every open Mark of +account+, in any hunt.
        def open_marks(account)
          @db[:hunt_marks].where(account_id: account, done_at: nil).map do |row|
            Mark.new(hunt: row[:hunt], step: row[:step], part: row[:part], opened_at: row[:opened_at])
          end
        end

        # When +account+ began the hunt +slug+ (epoch seconds), or +nil+.
        def started_at(account, slug) = marks(account, slug).min(:opened_at)

        # When step +step+ of the hunt +slug+ opened for +account+, or +nil+.
        def step_opened_at(account, slug, step) = marks(account, slug).where(step: step, part: 0).get(:opened_at)

        # Solves the open +mark+ (a Mark) of +account+ in +trail+ at +at+ and
        # opens the next part. Returns <tt>:part</tt> (the step goes on),
        # <tt>:step</tt> (the next step opened) or <tt>:home</tt> (the last
        # step was solved).
        def solve(account, trail, mark, at)
          marks(account, mark.hunt).where(step: mark.step, part: mark.part).update(done_at: at)
          step, part = next_of(trail, mark)
          return :home unless step

          @db[:hunt_marks].insert(account_id: account, hunt: mark.hunt, step: step, part: part, opened_at: at)
          part.zero? ? :step : :part
        end

        # How many hints of step +step+ (all steps without one) of the hunt
        # +slug+ +account+ saw.
        def hints_seen(account, slug, step = nil)
          rows = @db[:hunt_hints].where(account_id: account, hunt: slug)
          (step ? rows.where(step: step) : rows).count
        end

        # Keeps that +account+ saw hint +hint+ (0-based) of step +step+ at
        # +at+.
        def see_hint(account, slug, step, hint, at)
          @db[:hunt_hints].insert_conflict.insert(account_id: account, hunt: slug, step: step, hint: hint, seen_at: at)
        end

        # Keeps an answer of +account+ to step +step+ at +at+, right or not
        # (+ok+).
        def attempt(account, slug, step, ok, at)
          @db[:hunt_attempts].insert(account_id: account, hunt: slug, step: step, ok: ok ? 1 : 0, at: at)
        end

        # The answers +account+ gave in the hunt +slug+ since +since+, and
        # when it last answered wrong (or +nil+).
        def attempts(account, slug, since)
          rows = @db[:hunt_attempts].where(account_id: account, hunt: slug)
          [rows.where { at >= since }.count, rows.where(ok: 0).max(:at)]
        end

        # The seconds +account+ waits before it may answer in the hunt +slug+
        # at +now+: WRONG_WAIT after a wrong answer, a minute once it gave
        # ANSWERS_AN_HOUR in the last hour, else 0.
        def wait(account, slug, now = Time.now.to_i)
          count, wrong_at = attempts(account, slug, now - 3600)
          return 60 if count >= ANSWERS_AN_HOUR

          wrong_at ? [wrong_at + WRONG_WAIT - now, 0].max : 0
        end

        # Keeps that +account+ named +name+ finished +trail+ at +at+, in its
        # season or not (+season+), on the list or not (+ranked+). Returns
        # the finish (#finish_of).
        def finish(account, name, trail, at, season:, ranked:)
          @db[:hunt_finishes].insert_conflict.insert(
            account_id:  account,
            name:        name.to_s,
            hunt:        trail.slug,
            started_at:  started_at(account, trail.slug) || at,
            finished_at: at,
            hints:       hints_seen(account, trail.slug),
            season:      season ? 1 : 0,
            ranked:      ranked ? 1 : 0
          )
          finish_of(account, trail.slug)
        end

        # The finish of +account+ in the hunt +slug+: a Hash of +name+,
        # +started_at+, +finished_at+, +seconds+, +hints+, +season+ and
        # +rank+ (its place on the list, +nil+ off it), or +nil+.
        def finish_of(account, slug)
          row = @db[:hunt_finishes].where(account_id: account, hunt: slug).first or return nil

          place = board(slug, nil).index { |r| r['account_id'] == account }
          shaped(row).merge('rank' => place && (place + 1))
        end

        # The list of the hunt +slug+: the ranked finishes in its season, the
        # fewest hints first, then the shortest time, then the earliest;
        # Hashes as #finish_of without +rank+, at most +limit+ (+nil+ for
        # all).
        def board(slug, limit = 10)
          rows = @db[:hunt_finishes].where(hunt: slug, season: 1, ranked: 1).all.map { |row| shaped(row) }
          rows = rows.sort_by { |r| [r['hints'], r['seconds'], r['finished_at']] }
          limit ? rows.first(limit) : rows
        end

        # How many accounts began the hunt +slug+, and how many finished it.
        def players(slug)
          [@db[:hunt_marks].where(hunt: slug).select(:account_id).distinct.count, @db[:hunt_finishes].where(hunt: slug).count]
        end

        # How many accounts reached each step of the hunt +slug+, step
        # (1-based) => accounts.
        def reached(slug)
          @db[:hunt_marks].where(hunt: slug, part: 0).group_and_count(:step).to_h { |r| [r[:step] + 1, r[:count]] }
        end

        # Forgets everything of +account+ in the hunt +slug+.
        def reset(account, slug)
          %i[hunt_marks hunt_hints hunt_attempts hunt_finishes].each { |t| @db[t].where(account_id: account, hunt: slug).delete }
        end

        private

        def marks(account, slug) = @db[:hunt_marks].where(account_id: account, hunt: slug)

        def next_of(trail, mark)
          return [mark.step, mark.part + 1] if mark.part + 1 < trail.steps[mark.step].parts.size
          return [mark.step + 1, 0] if mark.step + 1 < trail.steps.size

          nil
        end

        def shaped(row)
          {
            'account_id'  => row[:account_id],
            'name'        => row[:name],
            'started_at'  => row[:started_at],
            'finished_at' => row[:finished_at],
            'seconds'     => row[:finished_at] - row[:started_at],
            'hints'       => row[:hints],
            'season'      => row[:season] == 1
          }
        end
      end

      # The tables of the hunts on the Central.
      MIGRATIONS = [
        <<~SQL
          CREATE TABLE hunt_marks (
            account_id INTEGER NOT NULL,
            hunt       TEXT NOT NULL,
            step       INTEGER NOT NULL,
            part       INTEGER NOT NULL,
            opened_at  INTEGER NOT NULL,
            done_at    INTEGER,
            PRIMARY KEY (account_id, hunt, step, part)
          );
          CREATE INDEX hunt_marks_open ON hunt_marks (account_id, done_at);
          CREATE TABLE hunt_hints (
            account_id INTEGER NOT NULL,
            hunt       TEXT NOT NULL,
            step       INTEGER NOT NULL,
            hint       INTEGER NOT NULL,
            seen_at    INTEGER NOT NULL,
            PRIMARY KEY (account_id, hunt, step, hint)
          );
          CREATE TABLE hunt_attempts (
            id         INTEGER PRIMARY KEY,
            account_id INTEGER NOT NULL,
            hunt       TEXT NOT NULL,
            step       INTEGER NOT NULL,
            ok         INTEGER NOT NULL,
            at         INTEGER NOT NULL
          );
          CREATE INDEX hunt_attempts_account ON hunt_attempts (account_id, hunt, at);
          CREATE TABLE hunt_finishes (
            account_id  INTEGER NOT NULL,
            name        TEXT NOT NULL,
            hunt        TEXT NOT NULL,
            started_at  INTEGER NOT NULL,
            finished_at INTEGER NOT NULL,
            hints       INTEGER NOT NULL,
            season      INTEGER NOT NULL,
            ranked      INTEGER NOT NULL,
            PRIMARY KEY (account_id, hunt)
          );
        SQL
      ].freeze
    end
  end
end
