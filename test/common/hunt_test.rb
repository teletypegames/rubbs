# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'
require 'tmpdir'

# The hunts: the parts, a file read as a Trail, the Book's checks, and the
# Central's service, played from the first clue to home through the badges'
# facts and answers.
class HuntTest < Minitest::Test
  Hunt   = Rubbs::Common::Hunt
  Badges = Rubbs::Common::Badges

  TRAIL = <<~YAML
    title: The Avian Route
    intro: Follow a message across the network.
    authors: [Zed]
    steps:
      - clue: Find the April document that flies datagrams on wings.
        find: { board: hackercave, event: read, kind: rfc, ref: '1149' }
        fragment: PIGEON
        hints: [It is an April RFC., Number 1149.]
      - clue: How heavy is a typical MTU?
        answer: ['256 mg', '256 milligrams']
      - clue: Read it, then name the bird.
        find: { board: hackercave, event: read, kind: rfc, ref: '2549' }
        answer: Pigeon
        fragment: OCEAN
  YAML

  def setup
    Badges.reset
    Rubbs.badges(:hackercave) { event :read, kind: 'k', ref: 'r' }
    Rubbs.badges(:network) do
      event :hunt_finished, ref: 'r', in_season: 's', hints: 'h', rank: 'r'
      badge(:hunter) { hint 'Finish a hunt.'; emblem '*'; on(:hunt_finished).once }
    end
    @dir = Dir.mktmpdir('hunts')
    FileUtils.mkdir_p(File.join(@dir, '2026'))
    write("w#{Date.today.cweek}-avian-route.yml", TRAIL, year: Date.today.cwyear)
  end

  def teardown
    Badges.reset
    Rubbs.config.auth_secrets = []
  end

  def write(name, text, year: 2026)
    FileUtils.mkdir_p(File.join(@dir, year.to_s))
    File.write(File.join(@dir, year.to_s, name), text)
  end

  def fact(ref, at: Time.now + 1)
    Badges::Fact.make(name: 'read', board: 'hackercave', fields: { kind: 'RFC', ref: ref }, at: at)
  end

  def test_the_parts
    find = Hunt::Find.new('board' => 'hackercave', 'event' => 'read', 'ref' => %w[1149 2549])
    assert find.match?(fact('2549'))
    refute find.match?(fact('1'))
    refute find.asks?
    colored = Hunt::Find.new('board' => 'x', 'event' => 'read', 'color' => 1)
    assert_equal ['the event read has no field color'], colored.problems(Badges.catalog)
    assert_equal ['no board reports the event dance'], Hunt::Find.new('board' => 'x', 'event' => 'dance').problems(Badges.catalog)
    answer = Hunt::Answer.new(['256 mg'])
    assert answer.accept?('256MG')
    assert Hunt::Answer.new('Ős Kő').accept?('os ko')
    assert_equal ['answer needs at least one answer'], Hunt::Answer.new([]).problems(nil)
  end

  # A proxy that answers a notice for every event.
  class NoticeProxy
    def call(_op, _actor, **) = { 'result' => 'ok', 'earned' => [], 'notices' => ['Step 1 solved.'] }
  end

  def test_a_declared_event_goes_and_its_notices_are_told
    assert Badges.catalog.counts?(:read, 'hackercave')
    refute Badges.catalog.counts?(:use, 'hackercave')
    Rubbs.config.badges = Badges::Reporter.new(NoticeProxy.new, board: 'hackercave')
    ada = Rubbs::Test::Session.new(identity: Rubbs::Common::Auth::Identity.new(id: 7, name: 'Ada', source: :login))
    assert ada.achieve(:read, kind: 'rfc', ref: '1')
    Rubbs.config.badges.flush
    assert_includes ada.output, 'Step 1 solved.'
  ensure
    Rubbs.config.badges = nil
  end

  def test_a_file_as_a_trail
    trail, problems = Hunt::Trail.read(File.join(@dir, '2026', 'x.yml').sub('x.yml', 'missing.yml'))
    assert_nil trail
    refute_empty problems
    write('w46-avian-route.yml', TRAIL)
    trail, problems = Hunt::Trail.read(File.join(@dir, '2026', 'w46-avian-route.yml'))
    assert_empty problems
    assert_equal '2026-w46-avian-route', trail.slug
    assert_equal Time.utc(2026, 11, 8, 23), trail.opens
    assert_equal Time.utc(2026, 11, 15, 23), trail.closes
    assert_equal %w[find answer], trail.steps.last.parts.map(&:key)
    assert_equal ['PIGEON'], trail.fragments(2)
  end

  def test_the_book_tells_what_is_wrong
    write('w46-a.yml', TRAIL)
    write('w46-b.yml', "title: B\nsteps:\n  - clue: x\n    find: { board: hackercave, event: dance }\n    colour: red\n")
    write('nameless.yml', "steps: []\n")
    problems = Hunt::Book.new(@dir).problems
    assert_includes problems, 'w46-b.yml: step 1: unknown key colour'
    assert_includes problems, 'w46-b.yml: step 1: no board reports the event dance'
    assert(problems.any? { |p| p.include?('its season meets the season of w46-') })
    assert(problems.any? { |p| p.start_with?('nameless.yml: no title') })
    assert(problems.any? { |p| p.include?('nameless.yml: no season') })
  end

  def test_a_hunt_played_home
    Rubbs::Test.auth_secret
    accounts = Rubbs::Test.accounts
    ada      = accounts.register('Ada', 'secret1')
    Hunt.directory = @dir
    services = [Badges::Service, Hunt::Service]
    server   = Rubbs::Common::Central::Server.new(services: services, accounts: accounts, data: Dir.mktmpdir)
    badges   = Rubbs::Common::Central::Proxy.local(Badges::Service, server, aud: 'hackercave-bbs')
    hunt     = Rubbs::Common::Central::Proxy.local(Hunt::Service, server, aud: 'ttg-gate-bbs')
    actor    = Rubbs::Common::Central::Actor.new(id: ada.id, name: 'Ada')

    guest = hunt.state(Rubbs::Common::Central::Actor.guest('Joe'))
    assert guest['guest']
    assert_includes guest['clue'], 'April document'
    assert_equal 'The Avian Route', hunt.trails['season']['title']

    assert_empty badges.record(actor, event: 'read', fields: { kind: 'rfc', ref: '1149' }, board: 'hackercave')['notices']
    state = hunt.state(actor)
    assert_equal 1, state['step']
    assert_equal 1, state['trail']['players']
    assert_equal 'not_yet', hunt.hint(actor, hunt: state['trail']['slug'])['result']
    slug = state['trail']['slug']

    sleep 1
    notices = badges.record(actor, event: 'read', fields: { kind: 'rfc', ref: '1149' }, board: 'hackercave')['notices']
    words = 'The Hunt, The Avian Route: step 1 solved. Your fragment: PIGEON. The next clue waits on your Hunt page.'
    assert_equal [words], notices
    state = hunt.state(actor, hunt: slug)
    assert_equal 2, state['step']
    assert state['asks']
    assert_equal ['PIGEON'], state['fragments']

    assert_equal 'wrong', hunt.answer(actor, hunt: slug, text: '12 kg')['result']
    assert_equal 'wait', hunt.answer(actor, hunt: slug, text: '256 mg')['result']
    server.services['/hunt'].engine.instance_variable_get(:@db)[:hunt_attempts].update(at: Time.now.to_i - 60)
    assert_equal 'right', hunt.answer(actor, hunt: slug, text: '256 mg')['result']
    assert_equal 'no_question', hunt.answer(actor, hunt: slug, text: 'Pigeon')['result']

    sleep 1
    badges.record(actor, event: 'read', fields: { kind: 'rfc', ref: '2549' }, board: 'hackercave')
    home = hunt.answer(actor, hunt: slug, text: 'pigeon')
    assert_equal 'right', home['result']
    assert_includes home['notices'].first, 'you made it home! You are number 1 on the list.'
    assert_includes home['notices'].last, 'Badge earned'
    finish = hunt.state(actor, hunt: slug)['finish']
    assert_equal 1, finish['rank']
    assert_equal 0, finish['hints']
    assert_equal(['Ada'], hunt.board(hunt: slug)['board'].map { |r| r['name'] })
  ensure
    Hunt.directory = nil
    server&.stop
  end
end
