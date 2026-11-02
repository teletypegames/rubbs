# frozen_string_literal: true

require 'test_helper'

# A window that lays itself out at any size, as MasterDetail does.
class SizableWindow < BBS::Window
  def resizable? = true
  def normal_rect = [10, 5, 40, 12]

  def place(x, y, width, height) = layout(x, y, width, height)
end

class WindowTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @app     = BBS::Application.new(session: @session, session_id: 's')
  end

  def teardown = @session.fake_line.close

  def window(klass = BBS::Window, **kw)
    win = klass.new(title: 'Win', **kw)
    win.layout(10, 5, 40, 12)
    @app.open_window(win)
  end

  def press(x, y, kind: :press, button: :left)
    BBS::Event.mouse(BBS::Telnet::MouseEvent.new(kind: kind, button: button, x: x, y: y))
  end

  def key(name) = BBS::Event.key(name)

  def test_the_close_gadget_and_the_close_key_close
    win = window
    assert_equal :close_window, win.handle_event(press(12, 5))
    assert_equal :close_window, win.handle_event(key(:escape))
    assert_nil win.handle_event(key('x'))
  end

  def test_f5_zooms_a_maximizable_resizable_window
    win = window(SizableWindow, maximizable: true)
    assert_equal :handled, win.handle_event(key(:f5))
    assert win.maximized?
    assert_equal @app.desktop_rect, [win.bounds.x, win.bounds.y, win.bounds.width, win.bounds.height]
    win.handle_event(key(:alt_enter))
    refute win.maximized?
  end

  def test_keyboard_move_moves_and_sizes_until_enter
    win = window(SizableWindow)
    win.handle_event(key(:ctrl_f5))
    assert win.busy?
    win.handle_event(key(:right))
    win.handle_event(key(:shift_down))
    assert_equal [11, 5, 40, 13], [win.bounds.x, win.bounds.y, win.bounds.width, win.bounds.height]
    assert_equal :handled, win.handle_event(key('q'))
    win.handle_event(key(:enter))
    refute win.busy?
  end

  def test_dragging_the_title_bar_moves_the_window
    win = window
    win.handle_event(press(20, 5))
    win.handle_event(press(25, 7, kind: :drag))
    win.handle_event(press(25, 7, kind: :release))
    assert_equal [15, 7], [win.bounds.x, win.bounds.y]
    refute win.busy?
  end

  def test_a_button_hotkey_presses_the_button
    win = window
    pressed = false
    button = BBS::Widgets::Button.new(label: '&Yes', on_click: ->(_) { pressed = true })
    button.layout(12, 8, 8, 1)
    win.add(button)
    win.reset_focus
    win.handle_event(key('y'))
    assert pressed
  end

  def test_tab_moves_the_focus_between_buttons
    win = window
    a, b = %w[&A &B].map { |l| BBS::Widgets::Button.new(label: l).tap { |w| w.layout(12, 8, 6, 1) } }
    [a, b].each { |w| win.add(w) }
    win.reset_focus
    assert_same a, win.focus_manager.focused
    assert_equal :handled, win.handle_event(key(:tab))
    assert_same b, win.focus_manager.focused
    win.handle_event(key(:shift_tab))
    assert_same a, win.focus_manager.focused
  end

  def test_render_draws_the_frame_title_and_gadgets
    win = window(SizableWindow, maximizable: true)
    frame = BBS::FrameBuffer.new(80, 24)
    win.render(frame)
    screen = frame.diff(BBS::FrameBuffer.new(80, 24))
    %w[[■] Win [↑] ┘ ╔].each { |part| assert_includes screen, part }
  end
end

class StatusbarTest < Minitest::Test
  def bar
    bar = BBS::Statusbar.new(right_text: 'node 1')
    bar.add_hint('F1', 'Help') { :help }
    bar.add_hint('Alt-X', 'Bye') { nil }
    bar.add_hint('Q', 'Quit', hidden: true) { :quit }
    bar.layout(1, 24, 80, 1)
    bar.theme = BBS::Theme.mono
    bar
  end

  def test_keys_run_their_hints
    assert_equal :help, bar.handle_event(BBS::Event.key(:f1))
    assert_equal :handled, bar.handle_event(BBS::Event.key(:alt_x))
    assert_equal :quit, bar.handle_event(BBS::Event.key('q'))
    assert_nil bar.handle_event(BBS::Event.key(:f2))
  end

  def test_a_click_runs_the_shown_hint_under_it
    click = BBS::Event.mouse(BBS::Telnet::MouseEvent.new(kind: :press, button: :left, x: 3, y: 24))
    assert_equal :help, bar.handle_event(click)
  end

  def test_render_shows_the_hints_and_the_right_text
    frame = BBS::FrameBuffer.new(80, 24)
    bar.render(frame)
    screen = frame.diff(BBS::FrameBuffer.new(80, 24))
    ['F1', ' Help ', 'node 1'].each { |part| assert_includes screen, part }
    refute_includes screen, 'Quit'
  end
end

class WindowSpecTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @app     = BBS::Application.new(session: @session, session_id: 's', services: { db: :the_db })
  end

  def teardown = @session.fake_line.close

  def test_a_form_gets_its_fields_and_callbacks_with_ctx
    seen = nil
    spec = BBS::WindowSpec.new(:compose, type: :form)
    spec.title { |ctx| " #{ctx[:who]} " }
    spec.prefill { { body: 'hello' } }
    spec.field :body, label: 'Body'
    spec.on_submit { |values, _form, ctx| seen = [values[:body], ctx[:db]]; :close }
    form = spec.open(@app, who: 'ada')
    assert_equal ' ada ', form.title
    form.instance_variable_get(:@options)[:on_submit].call({ body: 'x' }, form)
    assert_equal ['x', :the_db], seen
  end

  def test_a_master_detail_window_gets_defaults_and_bound_labels
    spec = BBS::WindowSpec.new(:list, type: :master_detail)
    spec.title 'List'
    spec.items { %w[a b] }
    spec.item_label { |item, ctx| "#{item}@#{ctx[:db]}" }
    win = spec.open(@app)
    assert_equal 'a@the_db', win.instance_variable_get(:@item_label).call('a')
    assert_equal [], BBS::WindowSpec::DEFAULTS[:master_detail][:render_detail].call(:x, 10)
  end
end

class ApplicationTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def run_app(input, &)
    @session.fake_line.caller.write(input)
    app = BBS::Application.define(&).build(session: @session, session_id: 's')
    Timeout.timeout(5) { app.run }
    app
  end

  def test_a_status_key_that_halts_ends_the_run
    pressed = []
    run_app("\eOP\e[21~") do
      status_hint('F1', 'Help') { pressed << :help; nil }
      status_hint('F10', 'Bye') { :halt }
    end
    assert_equal [:help], pressed
    assert_includes @session.received, 'Help'
  end

  def test_the_line_dropping_ends_the_run
    @session.fake_line.caller.close
    app = BBS::Application.new(session: @session, session_id: 's')
    Timeout.timeout(5) { app.run }
    assert app.line_lost?
  end

  def test_f6_and_alt_digits_switch_windows
    app = BBS::Application.new(session: @session, session_id: 's')
    one, two = %w[One Two].map { |t| app.open_window(BBS::Window.new(title: t)) }
    assert_equal [1, 2], [one.number, two.number]
    app.send(:dispatch, BBS::Event.key(:"alt_#{one.number}"))
    assert_same one, app.top_window
    app.send(:dispatch, BBS::Event.key(:f6))
    assert_same two, app.top_window
  end

  def test_a_window_closing_itself_is_closed
    app = BBS::Application.new(session: @session, session_id: 's')
    closed = nil
    app.open_window(BBS::Window.new(title: 'W', on_close: ->(w) { closed = w }))
    app.send(:dispatch, BBS::Event.key(:escape))
    assert_nil app.top_window
    refute_nil closed
  end

  def test_desktop_rect_leaves_the_bars
    app = BBS::Application.new(session: @session, session_id: 's')
    app.menubar = BBS::Menubar.new
    app.statusbar = BBS::Statusbar.new
    assert_equal [1, 2, 80, 22], app.desktop_rect
  end
end
