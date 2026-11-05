# frozen_string_literal: true

require 'test_helper'
require 'rubbs/test'

class BoardDefinitionTest < Minitest::Test
  APP = Rubbs::Modern::Application.define { theme :synchronet }

  class Shop
    include Rubbs::Common::Board::Domain

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
    @config = Rubbs.config.dup
    ENV['SHOP_BBS_LIMIT'] = '9'
    ENV['SHOP_BBS_LANGUAGES'] = 'hu, de'
    ENV['SHOP_BBS_OPEN'] = 'yes'
  end

  def teardown
    %w[SHOP_BBS_LIMIT SHOP_BBS_LANGUAGES SHOP_BBS_OPEN].each { |k| ENV.delete(k) }
    Rubbs.instance_variable_set(:@config, @config)
  end

  def test_the_names_come_from_the_title
    assert_equal 'ttg-blog-bbs', Rubbs::Common::Board::BoardDefinition.slug('TTG Blog BBS')
    board = Rubbs::Common::Board::BoardDefinition.new('Shop BBS', Shop) { modern APP }.configure
    assert_equal 'shop-bbs', Rubbs.config.log_tag
    assert_equal 'SHOP_BBS_', Rubbs.config.env_prefix
    assert_equal 'Shop BBS', Rubbs.config.title
    assert board.board.started
    assert_same board.board, Rubbs.config.board
  end

  def test_stop_runs_the_hooks_then_the_domains_stop
    stopped = []
    board = Rubbs::Common::Board::BoardDefinition.new('Shop BBS', Shop) do
      modern APP
      on_stop { |shop| stopped << shop.class }
    end.configure
    board.board.define_singleton_method(:stop) { stopped << :domain }
    board.stop
    assert_equal [Shop, :domain], stopped
    assert_equal [], Rubbs.config.health.call
  end

  def test_settings_take_the_type_of_their_default
    Rubbs::Common::Board::BoardDefinition.new('Shop BBS', Shop) { modern APP }.configure
    shop = Rubbs.config.board
    assert_equal 9, shop.limit
    assert_equal %w[hu de], shop.languages
    assert shop.open
    assert_equal File.expand_path('data/shop.sqlite3'), shop.db
    assert_equal({ stock: { limit: 9 }, till: [{ limit: 9 }] }, shop.services)
  end

  def test_one_face_needs_no_question_and_two_do
    one = Rubbs::Common::Board::BoardDefinition.new('Shop BBS') { modern APP }
    one.configure
    assert Rubbs.config.mouse_on_connect
    two = Rubbs::Common::Board::BoardDefinition.new('Shop BBS') do
      modern APP
      petscii Class.new(Rubbs::Petscii::Face)
    end
    two.configure
    refute Rubbs.config.mouse_on_connect
    assert_kind_of Rubbs::Common::Call::Flow::Steps::Call, two.flow.steps.first
  end

  def test_each_face_ends_with_the_goodbye_unless_it_has_its_own
    board = Rubbs::Common::Board::BoardDefinition.new('Shop BBS') do
      modern APP
      petscii(goodbye: false) { call { :done } }
      goodbye 'A note.'
    end
    modern  = board.send(:face_flow, APP, true)
    petscii = board.send(:face_flow, proc { call { nil } }, false)
    assert_kind_of Rubbs::Common::Call::Flow::Steps::Goodbye, modern.steps.last
    assert_equal 'A note.', modern.steps.last.note
    refute_kind_of Rubbs::Common::Call::Flow::Steps::Goodbye, petscii.steps.last
  end
end

class PresetTest < Minitest::Test
  def teardown = Rubbs.config.preset = Rubbs::Common::Board::Preset::NONE

  def test_the_user_agent_carries_the_presets_addition
    assert_equal Rubbs::Common::Board::Config::DEFAULT_USER_AGENT, Rubbs.config.user_agent
    Rubbs.config.preset = Rubbs::Common::Board::Preset.new(user_agent: '(+https://example.org)')
    assert_equal "#{Rubbs::Common::Board::Config::DEFAULT_USER_AGENT} (+https://example.org)", Rubbs.config.user_agent
  end
end

class SnapshotTest < Minitest::Test
  def test_the_newer_file_wins_and_a_refresh_swaps_in
    Dir.mktmpdir do |dir|
      seed = File.join(dir, 'seed.json.gz')
      data = File.join(dir, 'data', 'catalog.json.gz')
      Rubbs::Common::Storage::Snapshot.write(seed, { 'items' => %w[a] }, Time.utc(2026, 1, 1))
      Rubbs::Common::Storage::Snapshot.write(data, { 'items' => %w[a b] }, Time.utc(2026, 2, 1))
      snapshot = Rubbs::Common::Storage::Snapshot.new(seed: seed, path: data) { |r| Array(r['items']) }
      assert_equal %w[a b], snapshot.value
      assert_equal :ok, snapshot.refresh_if_older(0) { { 'items' => %w[c] } }
      assert_equal %w[c], snapshot.value
      assert_equal :fresh, snapshot.refresh_if_older(3600) { raise 'not asked' }
    end
  end

  def test_without_files_the_value_is_of_nothing
    snapshot = Rubbs::Common::Storage::Snapshot.new(seed: '/nonexistent', path: '/nonexistent2') { |r| Array(r['items']) }
    assert_equal [], snapshot.value
    assert_equal Rubbs::Common::Storage::Snapshot::NEVER, snapshot.generated_at
  end
end

class TransferTest < Minitest::Test
  def test_what_the_caller_is_told
    assert_match(/by ZMODEM/, Rubbs::Common::Files::Transfer.start(:zmodem, 'A.PRG', 100))
    assert_match(/save it as A.PRG/, Rubbs::Common::Files::Transfer.start(:xmodem, 'A.PRG', 100))
    assert_match(/up to 1023 bytes/, Rubbs::Common::Files::Transfer.result(:ok, :xmodem_1k, 'A.PRG'))
    assert_equal 'The download was cancelled.', Rubbs::Common::Files::Transfer.result(:cancelled, :zmodem, 'A.PRG')
  end

  def test_a_dropped_line_is_a_hangup
    Rubbs::Common::Files::Zmodem.stub(:send_files, :hangup) do
      assert_raises(Rubbs::Common::Line::Hangup) { Rubbs::Common::Files::Transfer.send(Rubbs::Test::Session.new, :zmodem, 'A', 'x') }
    end
  end
end

class FakeOSColorsTest < Minitest::Test
  def test_colours_by_name
    os = Rubbs::Common::FakeOS.define { colors text: :green, dim: { fg: :green, faint: true }, accent: "\e[1;33m" }
    assert_equal "\e[0m\e[32m", os.colors[:text]
    assert_equal "\e[0m\e[2;32m", os.colors[:dim]
    assert_equal "\e[1;33m", os.colors[:accent]
  end
end

class DoorTest < Minitest::Test
  def test_a_petscii_line_gets_the_petscii_program
    ran = []
    door = Rubbs::Common::Call::Door.new(:x, ->(_s, _c) { ran << :modern }, petscii: ->(_s, _c) { ran << :petscii }, about: 'X')
    door.run(Rubbs::Test::Session.new(petscii: true))
    door.run(Rubbs::Test::Session.new)
    assert_equal %i[petscii modern], ran
    assert_equal 'X', door.about
  end
end
