# frozen_string_literal: true

require 'test_helper'
require 'bbs/test'

class BoardDefinitionTest < Minitest::Test
  APP = BBS::Application.define { theme :synchronet }

  class Shop
    include BBS::Domain

    setting :limit, 5
    setting :languages, %w[en]
    setting :open, false
    path    :db, 'data/shop.sqlite3'

    service(:stock) { { limit: limit } }
    service(:till)  { [stock] }

    attr_reader :started

    def start
      @started = true
      super
    end
  end

  def setup
    @config = BBS.config.dup
    ENV['SHOP_BBS_LIMIT'] = '9'
    ENV['SHOP_BBS_LANGUAGES'] = 'hu, de'
    ENV['SHOP_BBS_OPEN'] = 'yes'
  end

  def teardown
    %w[SHOP_BBS_LIMIT SHOP_BBS_LANGUAGES SHOP_BBS_OPEN].each { |k| ENV.delete(k) }
    BBS.instance_variable_set(:@config, @config)
  end

  def test_the_names_come_from_the_title
    assert_equal 'ttg-blog-bbs', BBS::BoardDefinition.slug('TTG Blog BBS')
    board = BBS::BoardDefinition.new('Shop BBS', Shop) { modern APP }.configure
    assert_equal 'shop-bbs', BBS.config.log_tag
    assert_equal 'SHOP_BBS_', BBS.config.env_prefix
    assert_equal 'Shop BBS', BBS.config.title
    assert board.board.started
    assert_same board.board, BBS.config.board
  end

  def test_stop_runs_the_hooks_then_the_domains_stop
    stopped = []
    board = BBS::BoardDefinition.new('Shop BBS', Shop) do
      modern APP
      on_stop { |shop| stopped << shop.class }
    end.configure
    board.board.define_singleton_method(:stop) { stopped << :domain }
    board.stop
    assert_equal [Shop, :domain], stopped
    assert_equal [], BBS.config.health.call
  end

  def test_settings_take_the_type_of_their_default
    BBS::BoardDefinition.new('Shop BBS', Shop) { modern APP }.configure
    shop = BBS.config.board
    assert_equal 9, shop.limit
    assert_equal %w[hu de], shop.languages
    assert shop.open
    assert_equal File.expand_path('data/shop.sqlite3'), shop.db
    assert_equal({ stock: { limit: 9 }, till: [{ limit: 9 }] }, shop.services)
  end

  def test_one_face_needs_no_question_and_two_do
    one = BBS::BoardDefinition.new('Shop BBS') { modern APP }
    one.configure
    assert BBS.config.mouse_on_connect
    two = BBS::BoardDefinition.new('Shop BBS') do
      modern APP
      petscii Class.new(BBS::Petscii::Face)
    end
    two.configure
    refute BBS.config.mouse_on_connect
    assert_kind_of BBS::Flow::Steps::Call, two.flow.steps.first
  end

  def test_each_face_ends_with_the_goodbye_unless_it_has_its_own
    board = BBS::BoardDefinition.new('Shop BBS') do
      modern APP
      petscii(goodbye: false) { call { :done } }
      goodbye 'A note.'
    end
    modern  = board.send(:face_flow, APP, true)
    petscii = board.send(:face_flow, proc { call { nil } }, false)
    assert_kind_of BBS::Flow::Steps::Goodbye, modern.steps.last
    assert_equal 'A note.', modern.steps.last.note
    refute_kind_of BBS::Flow::Steps::Goodbye, petscii.steps.last
  end
end

class PresetTest < Minitest::Test
  def teardown = BBS.config.preset = BBS::Preset::NONE

  def test_the_user_agent_carries_the_presets_addition
    assert_equal BBS::Config::DEFAULT_USER_AGENT, BBS.config.user_agent
    BBS.config.preset = BBS::Preset.new(user_agent: '(+https://example.org)')
    assert_equal "#{BBS::Config::DEFAULT_USER_AGENT} (+https://example.org)", BBS.config.user_agent
  end
end

class SnapshotTest < Minitest::Test
  def test_the_newer_file_wins_and_a_refresh_swaps_in
    Dir.mktmpdir do |dir|
      seed = File.join(dir, 'seed.json.gz')
      data = File.join(dir, 'data', 'catalog.json.gz')
      BBS::Snapshot.write(seed, { 'items' => %w[a] }, Time.utc(2026, 1, 1))
      BBS::Snapshot.write(data, { 'items' => %w[a b] }, Time.utc(2026, 2, 1))
      snapshot = BBS::Snapshot.new(seed: seed, path: data) { |r| Array(r['items']) }
      assert_equal %w[a b], snapshot.value
      assert_equal :ok, snapshot.refresh_if_older(0) { { 'items' => %w[c] } }
      assert_equal %w[c], snapshot.value
      assert_equal :fresh, snapshot.refresh_if_older(3600) { raise 'not asked' }
    end
  end

  def test_without_files_the_value_is_of_nothing
    snapshot = BBS::Snapshot.new(seed: '/nonexistent', path: '/nonexistent2') { |r| Array(r['items']) }
    assert_equal [], snapshot.value
    assert_equal BBS::Snapshot::NEVER, snapshot.generated_at
  end
end

class TransferTest < Minitest::Test
  def test_what_the_caller_is_told
    assert_match(/by ZMODEM/, BBS::Transfer.start(:zmodem, 'A.PRG', 100))
    assert_match(/save it as A.PRG/, BBS::Transfer.start(:xmodem, 'A.PRG', 100))
    assert_match(/up to 1023 bytes/, BBS::Transfer.result(:ok, :xmodem_1k, 'A.PRG'))
    assert_equal 'The download was cancelled.', BBS::Transfer.result(:cancelled, :zmodem, 'A.PRG')
  end

  def test_a_dropped_line_is_a_hangup
    BBS::Zmodem.stub(:send_files, :hangup) do
      assert_raises(BBS::Hangup) { BBS::Transfer.send(BBS::Test::Session.new, :zmodem, 'A', 'x') }
    end
  end
end

class FakeOSColorsTest < Minitest::Test
  def test_colours_by_name
    os = BBS::FakeOS.define { colors text: :green, dim: { fg: :green, faint: true }, accent: "\e[1;33m" }
    assert_equal "\e[0m\e[32m", os.colors[:text]
    assert_equal "\e[0m\e[2;32m", os.colors[:dim]
    assert_equal "\e[1;33m", os.colors[:accent]
  end
end

class DoorTest < Minitest::Test
  def test_a_petscii_line_gets_the_petscii_program
    ran = []
    door = BBS::Door.new(:x, ->(_s, _c) { ran << :modern }, petscii: ->(_s, _c) { ran << :petscii }, about: 'X')
    door.run(BBS::Test::Session.new(petscii: true))
    door.run(BBS::Test::Session.new)
    assert_equal %i[petscii modern], ran
    assert_equal 'X', door.about
  end
end
