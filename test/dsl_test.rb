# frozen_string_literal: true

require 'test_helper'
require 'bbs/test'

class CommandDslTest < Minitest::Test
  module Shelf
    extend BBS::Part

    command(:shelf, 'Shelf', key: 'F3') { context[:taken] << :shelf }
  end

  def build(keys = [], &)
    @session = BBS::Test::Session.new(keys: keys)
    @context = { taken: [] }
    BBS::Application.define(&).build(session: @session, session_id: 's', context: @context)
  end

  def test_a_command_is_a_key_a_hint_and_a_menu_item
    app = build do
      command(:search, 'Search…', key: 'F2') { context[:taken] << :search }
      command(:secret, 'Secret', key: 'F9', hint: false) { context[:taken] << :secret }
      menu 'Wiki', :search, :separator, :log_off
    end
    assert_equal([['F2', 'Search', false], ['F9', 'Secret', true], %w[F10 Menu] + [false], ['Alt-X', 'Bye', false]],
                 app.statusbar.hints.map { |h| [h.key, h.label, h.hidden] })
    labels = app.menubar.menus.first.items.map(&:label)
    assert_equal ['&Search…', '', '&Log off'], labels
    app.statusbar.handle_event(BBS::Event.key(:f9))
    assert_equal [:secret], @context[:taken]
    assert_equal :halt, app.statusbar.handle_event(BBS::Event.key(:alt_x))
  end

  def test_parts_replay_their_declarations
    app = build { parts Shelf }
    app.statusbar.handle_event(BBS::Event.key(:f3))
    assert_equal [:shelf], @context[:taken]
  end

  def test_help_brings_about_pages_and_the_keys
    app = build do
      command(:search, 'Search…', key: 'F2') { nil }
      help about: 'About us.', reading: 'How to read.', keys: ['Space        vote']
    end
    help = app.menubar.menus.last
    assert_equal '&Help', help.label
    assert_equal ['&About', '&Reading', '&Keys'], help.items.map(&:label)
    keys = BBS::Application::Command.keys_page(app.statusbar.hints.map { nil }.compact, [])
    assert_includes keys, BBS::Application::Command::GENERIC_KEYS.first
  end

  def test_the_status_and_the_clock
    app = build { status { 'en.wikipedia.org' } }
    assert_match(/\Aen\.wikipedia\.org │ \d\d:\d\d\z/, app.statusbar.right_text)
    quiet = build { status(clock: false) { 'x' } }
    assert_equal 'x', quiet.statusbar.right_text
  end

  def test_services_become_readers
    app = build { services(catalog: :the_catalog) }
    assert_equal :the_catalog, app.catalog
  end

  def test_hotkeys_are_picked_where_free
    assert_equal '&Search', BBS::Application::Command.hotkeyed('Search', [])
    assert_equal 'S&tatus', BBS::Application::Command.hotkeyed('Status', ['s'])
    assert_equal 'E&xit', BBS::Application::Command.hotkeyed('E&xit', [])
  end
end

class DesktopDslTest < Minitest::Test
  class Ticker < BBS::Widget
    attr_reader :ticks

    def tick = (@ticks = ticks.to_i + 1)
    def render(_frame) = nil
  end

  def test_items_are_placed_by_words_and_widgets_made_per_call
    session = BBS::Test::Session.new
    builder = BBS::Application.define do
      desktop do
        art %w[AAAA BB], top: 1
        line 'tagline', bottom: 0, align: :right, margin: 2
        line(top: 5) { "#{1 + 1} lines" }
        widget(height: 2, middle: 0) { Ticker.new }
        on_show { context[:shown] = true }
      end
    end
    app = builder.build(session: session, session_id: 's', context: {})
    other = builder.build(session: session, session_id: 't', context: {})
    app.root.layout(1, 2, 80, 22)
    app.desktop.render(BBS::FrameBuffer.new(80, 24))
    labels = app.desktop.children.grep(BBS::Widgets::Label)
    art = labels.first(2).map { |l| [l.bounds.x, l.bounds.y] }
    assert_equal [[39, 3], [39, 4]], art
    tag = labels.find { |l| l.text == 'tagline' }
    assert_equal [72, 23], [tag.bounds.x, tag.bounds.y]
    assert(labels.any? { |l| l.text == '2 lines' })
    refute_same app.desktop.widget, other.desktop.widget
    app.tick!
    assert_equal 1, app.desktop.widget.ticks
    assert app.context[:shown]
  end
end

class ConveniencesTest < Minitest::Test
  def setup
    @app = BBS::Application.new(session: BBS::Test::Session.new, session_id: 's')
  end

  def test_loading_without_failed_returns_the_value
    assert_equal 42, @app.loading('Wait…') { 42 }
    assert_empty @app.windows
  end

  def test_loading_with_failed_tells_and_aborts
    assert_raises(BBS::Abort) { @app.loading('Wait…', failed: 'No answer.') { nil } }
    assert_equal 'Sorry', @app.top_window.title
    @app.close_all
    assert_raises(BBS::Abort) { @app.loading('Wait…', failed: 'No answer.') { raise 'down' } }
  end

  def test_an_abort_in_a_handler_is_quiet
    @app.statusbar = BBS::Statusbar.new
    @app.statusbar.add_hint('F2', 'Go') { raise BBS::Abort }
    assert_nil @app.send(:handle_safely, BBS::Event.key(:f2))
  end

  def test_report_and_paint
    assert_equal :too_fast, @app.report(:too_fast, { too_fast: 'Slow down.' })
    assert_equal 1, @app.windows.size
    assert_equal "#{@app.theme[:text_dim]}x#{@app.theme[:text]}", @app.dim('x')
  end

  def test_qr_opens_a_window
    window = @app.qr('HTTPS://EXAMPLE.ORG', title: 'Scan')
    assert_equal 'Scan', window.title
  end
end

class FaceTest < Minitest::Test
  class Shop
    def services = { stock: %w[apple pear] }
  end

  class Front < BBS::Petscii::Face
    title('SHOP') { "#{stock.size} items" }

    masthead do
      logo 'HI', colors: [CY] * 5
      line 'welcome', color: WH
      rule
    end

    main_menu do
      heading 'shop'
      item('l', 'list', 'what we have') { each_pick('STOCK', stock) { |item| context[:picked] << item } }
      item('x', 'fail', 'nothing') { fail_with('Sold out.') }
      log_off
    end
  end

  def test_the_main_menu_runs_items_until_log_off
    context = { picked: [] }
    session = BBS::Test::Session.new(keys: ['l', :enter, 'q', 'x', :enter, 'q'])
    face = Front.new(session, context, Shop.new)
    face.run
    assert_equal ['apple'], context[:picked]
    out = session.output
    assert_includes out, 'welcome'
    assert_includes out, '2 items'
    assert_includes out, 'Sold out.'
    assert_equal 'q', face.menu_cursor
  end

  def test_the_palette_and_constants
    assert_equal BBS::Petscii::Colors::LG, Front::LG
    assert_equal 40, Front::COLS
    face = Front.new(BBS::Test::Session.new, {}, Shop.new)
    assert_equal "#{Front::GR}x#{Front::LG}", face.dim('x')
  end
end

class ScreenHelpersTest < Minitest::Test
  def test_within_puts_the_title_back
    session = BBS::Test::Session.new
    screen = BBS::Petscii::Screen.new(session)
    screen.title('HOME', 'right')
    screen.within('INNER') { :inside }
    assert_equal %w[HOME right], screen.current_title
  end

  def test_prompt_and_number
    session = BBS::Test::Session.new(keys: [:enter, '1', '2', :enter, 'x', :enter])
    screen = BBS::Petscii::Screen.new(session)
    assert_nil screen.prompt('name')
    assert_equal 12, screen.number('how many', 1..20)
    assert_nil screen.number('how many', 1..20)
  end

  def test_rule_line_and_markdown
    screen = BBS::Petscii::Screen.new(BBS::Test::Session.new)
    assert_equal 38, BBS::FrameBuffer.visible_width(screen.rule_line) - 1
    assert(screen.markdown('**hi**').first.start_with?(' '))
  end
end

class WindowReaderTest < Minitest::Test
  def test_a_reader_pages_its_lines_and_says_where
    app = BBS::Application.new(session: BBS::Test::Session.new, session_id: 's')
    jumped = nil
    spec = BBS::WindowSpec.new(:rfc, :reader) do
      title 'RFC 1'
      lines { |width| Array.new(100) { |i| "line #{i} of #{width}" } }
      action('Top') { |reader| jumped = reader.jump(0) }
    end
    reader = spec.open(app)
    reader.jump(50)
    assert_equal 49, reader.view.scroll
    assert_match(%r{line \d+/100}, reader.send(:where))
    assert reader.maximizable
    assert_nil jumped
  end
end

class WindowStreamTest < Minitest::Test
  def test_a_stream_keeps_the_text_only_when_asked
    app = BBS::Application.new(session: BBS::Test::Session.new, session_id: 's')
    said = []
    spec = BBS::WindowSpec.new(:chat, :stream) do
      title 'Chat'
      lines ['hello']
      on_submit { |text| said << text; keep if text == 'again' }
    end
    window = spec.open(app)
    submit = window.instance_variable_get(:@options)[:on_submit]
    assert_nil submit.call('hi', app)
    assert_equal :keep, submit.call('again', app)
    assert_equal %w[hi again], said
  end
end

class GapsTest < Minitest::Test
  class Menu < BBS::Petscii::Face
    masthead { line 'MASTHEAD' }

    main_menu(above: -> { 'ABOVE' }) do
      each_of(-> { %w[a b] }) { |name, i| item((i + 1).to_s, name) { context[:took] << name } }
      item('x', 'hidden', if: -> { false }) { nil }
      log_off
    end
  end

  def test_the_first_menu_stays_under_the_masthead
    session = BBS::Test::Session.new(keys: %w[2 q])
    face = Menu.new(session, { took: [] })
    face.run
    first = session.output.split("\e[2J")
    assert(first.any? { |part| part.include?('MASTHEAD') && part.include?('ABOVE') })
    assert_equal ['b'], face.context[:took]
    refute_includes session.output, 'hidden'
  end

  def test_an_action_without_a_parameter_runs_on_an_empty_list
    app = BBS::Application.new(session: BBS::Test::Session.new, session_id: 's')
    ran = []
    spec = BBS::WindowSpec.new(:list, :master_detail) do
      items { [] }
      meta 'plain'
      action('Reload') { ran << :reload }
      action('Open') { |item| ran << item }
    end
    window = spec.open(app)
    window.instance_variable_get(:@actions).first(2).each { |a| a[:on_click].call(window) }
    assert_equal [:reload], ran
  end

  class Settings
    include BBS::Domain

    setting :feed_list, 'x', env: 'FEEDS'
    setting :irc, 'irc.libera.chat', blank: true
    background('never', if: -> { false }) { raise 'not started' }
  end

  def test_settings_with_their_own_names_and_blanks
    ENV['GAPS_TEST_SETTINGS_FEEDS'] = 'y'
    ENV['GAPS_TEST_SETTINGS_IRC'] = ''
    config = BBS.config.env_prefix
    BBS.config.env_prefix = nil
    Settings.env_prefix 'GAPS_TEST_SETTINGS_'
    settings = Settings.new
    assert_equal 'y', settings.feed_list
    assert_nil settings.irc
    settings.start
  ensure
    BBS.config.env_prefix = config
    %w[GAPS_TEST_SETTINGS_FEEDS GAPS_TEST_SETTINGS_IRC].each { |k| ENV.delete(k) }
  end

  def test_the_clock_before_and_built_ins_in_their_place
    app = BBS::Application.define do
      command(:log_off, 'Leave', key: 'Alt-X', hint: 'Leave') { log_off }
      command(:go, 'Go', key: 'F2') { nil }
      menu 'Board', :go
      help({ 'Jargon File' => 'text' }, about: 'us')
      status(clock: :before) { 'x' }
    end.build(session: BBS::Test::Session.new, session_id: 's')
    assert_equal %w[F2 F10 Alt-X], app.statusbar.hints.map(&:key)
    assert_equal 'Leave', app.statusbar.hints.last.label
    assert_match(/\A\d\d:\d\d │ x\z/, app.statusbar.right_text)
    assert_includes app.menubar.menus.last.items.map(&:label), '&Jargon File'
  end

  def test_a_halting_face_flow_still_says_goodbye
    board = BBS::BoardDefinition.new('Gap BBS') { modern { gate(denied: 'No.') { false } } }
    flow = board.send(:face_flow, proc { gate(denied: 'No.') { false } }, true)
    assert_kind_of BBS::Flow::Steps::Nested, flow.steps.first
    assert_kind_of BBS::Flow::Steps::Goodbye, flow.steps.last
  end
end
