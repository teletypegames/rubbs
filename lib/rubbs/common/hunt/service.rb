# frozen_string_literal: true

module Rubbs
  module Common
    module Hunt
      # The hunts as a service of the Central, on <tt>/hunt</tt>, beside
      # Rubbs::Common::Badges::Service: it watches the facts the badges keep
      # (Badges.observe), so a Find part is solved on whichever board the
      # caller goes to, and the notice of it comes back with the badges. A
      # finished hunt is a +hunt_finished+ fact for the badges (+ref+ the
      # slug, +in_season+ yes or no, +hints+, +rank+). Ops:
      #
      # [trails] (anyone) the hunt in its +season+ and the +past+ ones (#summary)
      # [state]  +hunt+ (default the one in season, else the latest): where
      #          the caller is (#state); an account begins the hunt by it, a
      #          guest sees the first clue
      # [answer] +hunt+, +text+: an answer to the open part; +right+,
      #          +wrong+, +wait+ (+seconds+) or +no_question+, with the
      #          +notices+ (the badges a finish earned among them)
      # [hint]   +hunt+: the next hint of the step (+hint+), +not_yet+
      #          (+at+) or +no_hint+
      # [board]  (anyone) +hunt+: the list of its season (Engine#board)
      # [reset]  (sysop) +account_id+, +hunt+: forgets an account's hunt
      class Service < Central::Service
        path     '/hunt'
        database :hunt, MIGRATIONS

        # The Engine on the service's database.
        attr_reader :engine

        # The Book of the hunts.
        attr_reader :book

        # The service with the Central's +context+ and the hunts of +book+
        # (Hunt.book by default); it watches the badges' facts.
        def initialize(context, book: Hunt.book)
          super(context)
          @book   = book
          @engine = Engine.new(database)
          Badges.observe(:hunt, self)
        end

        op(:trails, actor: false) do |_, **|
          { season: (t = book.in_season) && summary(t), past: book.past.map { |trail| summary(trail) } }
        end

        op(:state) do |actor, hunt: nil, **|
          trail = pick(hunt) or next :no_hunt

          state(actor, trail)
        end

        op(:answer) do |actor, hunt:, text:, **|
          next :guest if actor.guest?

          trail = book[hunt] or next :no_hunt
          answer(actor, trail, text.to_s)
        end

        op(:hint) do |actor, hunt:, **|
          next :guest if actor.guest?

          trail = book[hunt] or next :no_hunt
          hint(actor, trail)
        end

        op(:board, actor: false) do |_, hunt:, **|
          { board: engine.board(hunt.to_s).map { |row| row.except('account_id') } }
        end

        op(:reset, role: :sysop) do |_, account_id:, hunt:, **|
          engine.reset(account_id.to_i, hunt.to_s)
          :ok
        end

        # The notices for +fact+ (a Rubbs::Common::Badges::Fact) of +actor+:
        # every open part of the account's hunts the fact solves, from the
        # moment the part opened (Badges.observers).
        def observe(actor, fact)
          engine.open_marks(actor.id).flat_map do |mark|
            trail = book[mark.hunt]
            trail && solves?(trail, mark, fact) ? advance(actor, trail, mark, fact.at) : []
          end
        end

        # A hunt as the ops answer it: +slug+, +title+, +intro+, +opens+ and
        # +closes+ (epoch seconds), +steps+, +season+, +players+ and
        # +finished+ (how many).
        def summary(trail)
          players, finished = engine.players(trail.slug)
          {
            slug:     trail.slug,
            title:    trail.title,
            intro:    trail.intro,
            opens:    trail.opens.to_i,
            closes:   trail.closes.to_i,
            steps:    trail.steps.size,
            season:   trail.season?,
            players:  players,
            finished: finished
          }
        end

        # Where +actor+ is in +trail+ (it begins it, an account): the hunt
        # (#summary), the +step+ (1-based) and its +clue+, whether it +asks+
        # an answer, the +fragments+ found, the +hints+ seen, +hints_total+,
        # when the next hint comes (+next_hint_at+), the seconds to +wait+
        # before an answer, and the +finish+ (Engine#finish_of) when it is
        # over. A guest gets the hunt, the first clue and +guest+.
        def state(actor, trail)
          engine.start(actor.id, trail, Time.now.to_i) unless actor.guest?
          base = { trail: summary(trail), steps: trail.steps.size }
          return base.merge(guest: true, step: 1, clue: trail.steps.first.clue) if actor.guest?

          base.merge(progress(actor, trail))
        end

        private

        def pick(slug)
          return book[slug] if slug && !slug.to_s.empty?

          book.in_season || book.past.first
        end

        def solves?(trail, mark, fact)
          part = trail.steps[mark.step]&.parts&.[](mark.part)
          !part.nil? && fact.at >= mark.opened_at && part.match?(fact)
        end

        def part_of(trail, mark) = trail.steps[mark.step].parts[mark.part]

        def seen(actor, trail, mark) = engine.hints_seen(actor.id, trail.slug, mark.step)

        def progress(actor, trail)
          finish = engine.finish_of(actor.id, trail.slug)
          return { finish: finish, fragments: trail.fragments(trail.steps.size) } if finish

          playing(actor, trail, engine.current(actor.id, trail.slug))
        end

        def playing(actor, trail, mark)
          step = trail.steps[mark.step]
          part = step.parts[mark.part]
          {
            step:      mark.step + 1,
            clue:      step.clue,
            asks:      part.asks?,
            kind:      part.key,
            fragments: trail.fragments(mark.step),
            **hint_state(actor, trail, mark),
            wait:      engine.wait(actor.id, trail.slug)
          }
        end

        def hint_state(actor, trail, mark)
          hints = trail.steps[mark.step].hints
          seen  = seen(actor, trail, mark)
          { hints: hints.first(seen), hints_total: hints.size, next_hint_at: next_hint_at(actor, trail, mark.step, seen) }
        end

        def next_hint_at(actor, trail, step, seen)
          return nil if seen >= trail.steps[step].hints.size

          engine.step_opened_at(actor.id, trail.slug, step).to_i + HINT_AFTER[seen]
        end

        def answer(actor, trail, text)
          mark = engine.current(actor.id, trail.slug)
          return :no_question unless mark && part_of(trail, mark).asks?

          seconds = engine.wait(actor.id, trail.slug)
          return { result: 'wait', seconds: seconds } if seconds.positive?

          judge(actor, trail, mark, text)
        end

        def judge(actor, trail, mark, text)
          now   = Time.now.to_i
          right = part_of(trail, mark).accept?(text)
          engine.attempt(actor.id, trail.slug, mark.step, right, now)
          right ? { result: 'right', notices: advance(actor, trail, mark, now) } : :wrong
        end

        def hint(actor, trail)
          mark = engine.current(actor.id, trail.slug) or return :no_hint
          seen = seen(actor, trail, mark)
          at   = next_hint_at(actor, trail, mark.step, seen) or return :no_hint
          return { result: 'not_yet', at: at } if Time.now.to_i < at

          reveal(actor, trail, mark, seen)
        end

        def reveal(actor, trail, mark, seen)
          engine.see_hint(actor.id, trail.slug, mark.step, seen, Time.now.to_i)
          { hint: trail.steps[mark.step].hints[seen] }
        end

        def advance(actor, trail, mark, at)
          case engine.solve(actor.id, trail, mark, at)
          when :part then []
          when :step then [Notices.found(trail, mark.step)]
          else home(actor, trail, at)
          end
        end

        def home(actor, trail, at)
          season = at < trail.closes.to_i
          ranked = season && !trail.authors.include?(actor.name) && !actor.role?(:sysop)
          finish = engine.finish(actor.id, actor.name, trail, at, season: season, ranked: ranked)
          earned = Badges.recorder&.keep(actor, Notices.fact(trail, finish)) || []
          [Notices.home(trail, finish), *earned.map { |b| Badges.announcement(b) }]
        end
      end
    end
  end
end
