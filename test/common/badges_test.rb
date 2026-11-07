# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'
require 'rubbs/common/board/check'

# The badges: the rules and their measures, the catalog's checks, the
# engine's tiers and composites, the Central's service, the board's reporter
# and the notice a caller sees.
class BadgesTest < Minitest::Test
  Badges = Rubbs::Common::Badges

  NOON = Time.utc(2026, 11, 7, 11)

  def setup
    Badges.reset
    Badges.catalog.boards = %w[wiki feedia hackercave]
  end

  def teardown
    Badges.reset
    Rubbs.config.badges = nil
    Rubbs.config.auth_secrets = []
  end

  def fact(name, board: 'wiki', at: NOON, call: 'c1', **fields)
    Badges::Fact.make(name: name, board: board, fields: fields, at: at, call: call)
  end

  def define_network
    Rubbs.badges :network do
      badge :tourist do
        title  'Tourist'
        hint   'Call two different boards.'
        emblem '♦', :cyan
        on(:call).distinct(:board).reaches 2
      end
      badge :globetrotter do
        title 'Globetrotter'
        hint  'Call every board.'
        emblem '*', :yellow
        on(:call).distinct(:board).reaches :all_boards
      end
      badge :regular do
        hint 'Call on days in a row.'
        emblem 'R', :red
        on(:call).streak(:days).tiers bronze: 2, silver: 3
      end
      badge :night_owl, secret: true do
        hint 'Call at night.'
        emblem 'O', :blue
        on(:call, hour: 0...4).once
      end
      badge :completionist do
        hint 'Tourist and Regular.'
        emblem '!', :white
        all_of :tourist, :regular
      end
    end
  end

  def test_the_measures
    facts = [fact('read', kind: 'rfc', ref: '1'), fact('read', kind: 'rfc', ref: '1'),
             fact('read', kind: 'rfc', ref: '2', call: 'c2')]
    assert_equal 3, Badges::Rule.new(:read).count.value(facts)
    assert_equal 2, Badges::Rule.new(:read).distinct(:ref).value(facts)
    assert_equal 2, Badges::Rule.new(:read).count.within(:call).value(facts)
    assert_equal 1, Badges::Rule.new(:read).once.value(facts)
    assert_equal 90.0, Badges::Rule.new(:hangup).sum(:minutes).value([fact('hangup', minutes: 30), fact('hangup', minutes: 60)])
    days = [0, 1, 2, 4].map { |d| fact('call', at: NOON + (d * 86_400)) }
    assert_equal 3, Badges::Rule.new(:call).streak(:days).value(days)
    assert_raises(ArgumentError) { Badges::Rule.new(:call).within(:month) }
  end

  def test_the_filters_and_the_derived_fields
    night = fact('call', at: Time.utc(2026, 10, 30, 23, 30))
    assert_equal 0, night.field('hour')
    assert_includes night.field('season'), 'pumpkin'
    assert Badges::Rule.new(:call, hour: 0...4, season: :pumpkin).match?(night)
    refute Badges::Rule.new(:call, hour: 0...4).match?(fact('call'))
    assert Badges::Rule.new(:read, kind: %w[rfc ien]).match?(fact('read', kind: 'ien'))
    assert Badges::Rule.new(:read, ref: /\A11/).match?(fact('read', ref: '1149'))
    refute Badges::Rule.new(:read, board: 'hackercave').match?(fact('read'))
  end

  def test_a_boards_badge_counts_its_own_events
    set = Rubbs.badges(:hackercave) do
      event :read, kind: String, ref: String
      badge(:reader) { hint 'Read.'; emblem 'R'; on(:read).count.reaches 1 }
      badge(:anywhere) { hint 'Call.'; emblem 'A'; on(:call, board: :any).once }
    end
    assert_equal({ 'board' => 'hackercave' }, set.badges.first.rule.filter)
    assert_empty set.badges.last.rule.filter
    assert Badges.catalog.counts?(:read, 'hackercave', kind: 'rfc')
    refute Badges.catalog.counts?(:read, 'wiki', kind: 'rfc')
  end

  def test_the_catalog_finds_what_is_wrong
    Rubbs.badges :wiki do
      badge(:no_event) { hint 'x'; emblem 'x'; on(:dance).once }
      badge(:no_field) { hint 'x'; emblem 'x'; on(:call, mood: 'good').once }
      badge(:bad_tiers) { hint 'x'; emblem 'x'; on(:call).count.tiers gold: 10, bronze: 1 }
      badge(:bare) { on(:call).once }
      badge(:parts) { hint 'x'; emblem 'x'; all_of :nothing }
    end
    problems = Badges.catalog.problems.join("\n")
    assert_includes problems, 'no board reports the event dance'
    assert_includes problems, 'the event call has no field mood'
    assert_includes problems, 'badge bad_tiers: the tiers are not in order'
    assert_includes problems, 'badge bare: no hint'
    assert_includes problems, 'badge bare: no emblem'
    assert_includes problems, 'nothing is no badge'
    assert_raises(ArgumentError) { Rubbs.badges(:wiki) { badge(:bare) { on(:call).once } } }
  end

  def engine
    define_network
    db = Rubbs::Common::Storage::Database.open(File.join(Dir.mktmpdir('badges'), 'b.sqlite3'), Badges::MIGRATIONS)
    Badges::Engine.new(db, Badges.catalog)
  end

  def test_the_engine_gives_tiers_and_composites_once
    e = engine
    assert_empty e.record(1, 'Ada', fact('call', board: 'wiki'))
    earned = e.record(1, 'Ada', fact('call', board: 'feedia', at: NOON + 86_400))
    assert_equal([%w[tourist], %w[regular bronze], %w[completionist]], earned.map { |a| [a.badge.key, a.tier].compact })
    assert_empty e.record(1, 'Ada', fact('call', board: 'feedia', at: NOON + 86_500))
    earned = e.record(1, 'Ada', fact('call', board: 'hackercave', at: NOON + (2 * 86_400)))
    assert_equal([%w[globetrotter], %w[regular silver]], earned.map { |a| [a.badge.key, a.tier].compact })
    progress = e.progress(1).to_h { |p| [p['key'], p] }
    assert_equal 3, progress['regular']['value']
    assert_equal [['bronze', 2], ['silver', 3]], progress['regular']['goals']
    assert_equal 0, progress['night_owl']['value']
    assert_equal 1, e.hall.find { |h| h['key'] == 'tourist' }['count']
  end

  def test_the_service_on_the_central
    define_network
    Rubbs::Test.auth_secret
    accounts = Rubbs::Test.accounts
    ada      = accounts.register('Ada', 'secret1')
    server   = Rubbs::Common::Central::Server.new(services: [Badges::Service], accounts: accounts, data: Dir.mktmpdir('central'))
    proxy    = Rubbs::Common::Central::Proxy.local(Badges::Service, server, aud: 'wiki-bbs')
    actor    = Rubbs::Common::Central::Actor.new(id: ada.id, name: 'Ada')
    assert_equal 'guest', proxy.record(Rubbs::Common::Central::Actor.guest('Joe'), event: 'call')['result']
    proxy.record(actor, event: 'call', board: 'wiki')
    answer = proxy.record(actor, event: 'call', board: 'feedia')
    assert_equal(['Tourist'], answer['earned'].map { |b| b['title'] })
    assert_equal 'cyan', answer['earned'].first['color']
    assert_equal 'forbidden', proxy.grant(actor, account_id: ada.id, name: 'Ada', badge: 'tourist')['result']
    assert_equal 2, proxy.mine(actor)['badges'].find { |b| b['key'] == 'tourist' }['value']
  ensure
    server&.stop
  end

  # A proxy that answers what the Central would, and keeps the requests.
  class FakeProxy
    attr_reader :requests

    def initialize(earned) = (@earned = earned) && (@requests = [])

    def call(op, actor, **fields)
      @requests << [op, actor.name, fields]
      { 'result' => 'ok', 'earned' => @earned }
    end
  end

  def test_the_reporter_sends_a_signed_in_callers_events_and_announces
    define_network
    proxy = FakeProxy.new([{ 'title' => 'Tourist', 'emblem' => '♦', 'hint' => 'Call two boards.', 'tier' => nil }])
    Rubbs.config.badges = Badges::Reporter.new(proxy, board: 'wiki')
    guest = Rubbs::Test::Session.new
    refute Badges.called(guest)
    ada = Rubbs::Test::Session.new(identity: Rubbs::Common::Auth::Identity.new(id: 7, name: 'Ada', source: :login))
    assert Badges.called(ada)
    refute Badges.called(ada)
    refute ada.achieve(:dance)
    Rubbs.config.badges.flush
    assert_equal [[:record, 'Ada', { event: 'call', fields: {}, call: 'test', via: nil, board: 'wiki' }]], proxy.requests
    assert_includes ada.output, 'Badge earned: ♦ Tourist. Call two boards.'
  end

  def test_the_check_reads_a_boards_badges
    dir = Dir.mktmpdir('board')
    File.write(File.join(dir, 'badges.rb'), "Rubbs.badges(:wiki) { badge(:odd) { emblem 'x'; on(:dance).once } }\n")
    findings = Rubbs::Common::Board::Check.run(dir).select { |f| f.rule == :badges }.map(&:message)
    assert_equal ['badge odd: no hint', 'badge odd: no board reports the event dance'], findings
    assert_empty Badges.catalog.badges
  end

  def test_the_caller_of_the_thread_achieves
    define_network
    Rubbs.badges(:wiki) { event :read; badge(:reader) { hint 'Read.'; emblem 'R'; on(:read).once } }
    proxy = FakeProxy.new([])
    Rubbs.config.badges = Badges::Reporter.new(proxy, board: 'wiki')
    assert_nil Rubbs.achieve(:read)
    ada = Rubbs::Test::Session.new(identity: Rubbs::Common::Auth::Identity.new(id: 7, name: 'Ada', source: :login))
    Rubbs::Common::Log.with_session('s1', caller: ada) { assert Rubbs.achieve(:read) }
    Rubbs.config.badges.flush
    assert_equal(['read'], proxy.requests.map { |r| r[2][:event] })
  end

  # A page with nothing on it.
  class Blank < Rubbs::Common::Screens::Page
    key('q') { quit }

    def draw(frame) = print_lines(frame, ['A page'])
  end

  def test_pages_show_an_announcement_as_a_notice
    line = Rubbs::Test::Session.new(keys: [->(l) { l.announce('Badge earned: ♦ Tourist.') }, 'x', ' ', 'q'])
    Rubbs::Common::Screens::Pages.new(line).run(Blank.new)
    assert_includes line.output, 'Badge earned: ♦ Tourist.'
    assert_includes line.output, 'Press a key'
    assert_nil line.announcer
  end
end
