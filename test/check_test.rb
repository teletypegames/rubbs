# frozen_string_literal: true

require 'test_helper'
require 'bbs/check'
require 'fileutils'

class CheckTest < Minitest::Test
  BOARD = {
    'bbs.rb'                                   => "require 'bbs'\nrequire_relative 'lib/domain'\n\n" \
                                                  "BBS.board 'Shop BBS', ShopBBS do\n  modern APP\nend\n",
    'Rakefile'                                 => '',
    'Gemfile'                                  => '',
    'Gemfile.lock'                             => '',
    'README.md'                                => '',
    'lib/domain.rb'                            => '',
    'lib/domain/shop_bbs.rb'                   => "class ShopBBS\n  include BBS::Domain\nend\n",
    'lib/domain/model/item_model.rb'           => "ItemModel = Data.define(:name)\n",
    'lib/domain/repository/item_repository.rb' => "class ItemRepository\nend\n",
    'lib/domain/service/item_service.rb'       => "class ItemService\nend\n",
    'lib/ui/modern.rb'                         => '',
    'lib/ui/petscii.rb'                        => '',
    'lib/ui/wording.rb'                        => '',
    'test/test_helper.rb'                      => '',
    'test/item_test.rb'                        => "require 'test_helper'\n"
  }.freeze

  def with_board(changes = {})
    Dir.mktmpdir do |dir|
      BOARD.merge(changes).each do |path, text|
        next if text.nil?

        FileUtils.mkdir_p(File.join(dir, File.dirname(path)))
        File.write(File.join(dir, path), text)
      end
      yield dir
    end
  end

  def test_a_board_in_shape_has_no_findings
    with_board { |dir| assert_empty BBS::Check.run(dir) }
  end

  def test_what_is_out_of_shape_is_named_with_its_rule
    changes = {
      'bbs.rb'                             => 'BBS.configure { |c| c.flow = ' \
                                              "BBS::Terminal.flow(title: 'X', modern: a, petscii: b) }\n",
      'lib/ui/words.rb'                    => '',
      'lib/ui/petscii.rb'                  => nil,
      'lib/domain/service/item_service.rb' => "class Items\nend\n",
      'lib/ui/modern.rb'                   => "x = ENV.fetch('X')\n"
    }
    with_board(changes) do |dir|
      rules = BBS::Check.run(dir).map(&:rule).uniq.sort
      assert_equal %i[bbs_rb domain faces names old_forms wording], rules
    end
  end

  def test_a_board_says_what_it_differs_in
    with_board('lib/ui/petscii.rb' => nil, 'lib/ui/modern.rb' => nil) do |dir|
      refute_empty BBS::Check.run(dir)
      assert_empty BBS::Check.run(dir, faces: false)
      assert_empty BBS::Check.run(dir, skip: [:faces])
    end
  end

  def test_the_declaration_and_the_names
    with_board('bbs.rb' => "BBS.board 'WarpEngine BBS', WarpEngineBBS, slug: 'warp-engine-bbs' do\nend\n") do |dir|
      board = BBS::Check::Board.new(dir)
      assert_equal 'warp-engine-bbs', board.slug
      assert_equal 'WARP_ENGINE_BBS_', board.env_prefix
      assert_equal 'WarpEngineBBS', board.declaration[:domain]
    end
    assert_equal 'TTGBlogBBS', BBS::Check.class_name('lib/domain/ttg_blog_bbs.rb')
  end

  def test_tables_need_models_and_sql_stays_in_them
    changes = {
      'lib/domain/migrations.rb'                 => "MIGRATIONS = ['CREATE TABLE items (id INTEGER PRIMARY KEY)', " \
                                                    "'CREATE TABLE tags (id INTEGER)'].freeze\n",
      'lib/domain/model/item_model.rb'           => "class ItemModel < BBS::Model\n  table :items\nend\n",
      'lib/domain/service/item_service.rb'       => "class ItemService\n  def all = db.fetch('SELECT * FROM items')\nend\n",
      'lib/domain/repository/item_repository.rb' => "class ItemRepository\n  Q = 'SELECT ?item WHERE { }'\nend\n"
    }
    with_board(changes) do |dir|
      findings = BBS::Check.run(dir).map { |f| [f.rule, f.path] }
      assert_includes findings, [:models, 'lib/domain/model/']
      assert_includes findings, [:raw_sql, 'lib/domain/service/item_service.rb']
      refute_includes findings, [:raw_sql, 'lib/domain/repository/item_repository.rb']
    end
  end

  def test_a_domain_named_unlike_its_board_says_its_prefix
    bbs = "BBS.board 'HackerCave BBS', HackerCaveBBS do\nend\n"
    with_board('bbs.rb' => bbs) do |dir|
      assert_equal [:env_prefix], BBS::Check.run(dir).map(&:rule).uniq
    end
    with_board('bbs.rb' => bbs, 'lib/domain/shop_bbs.rb' => "class HackerCaveBBS\n  include BBS::Domain\n\n  " \
                                                            "env_prefix 'HACKERCAVE_BBS_'\nend\n") do |dir|
      assert_empty BBS::Check.run(dir)
    end
  end

  def test_the_settings_name_their_variables
    klass = Class.new { include BBS::Domain }
    klass.env_prefix 'SHOP_BBS_'
    klass.setting :limit, 5
    klass.path :list, 'x.yml', env: 'ITEMS'
    assert_equal %w[SHOP_BBS_LIMIT SHOP_BBS_ITEMS], klass.environment_variables
  end
end
