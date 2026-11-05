# frozen_string_literal: true

require 'test_helper'

# A window that lays itself out at any size, as MasterDetail does.
class SizableWindow < Rubbs::Modern::Window
  def resizable? = true
  def normal_rect = [10, 5, 40, 12]

  def place(x, y, width, height) = layout(x, y, width, height)
end

class WindowTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @app     = Rubbs::Modern::Application.new(session: @session, session_id: 's')
  end

  def teardown = @session.fake_line.close

  def window(klass = Rubbs::Modern::Window, **kw)
    win = klass.new(title: 'Win', **kw)
    win.layout(10, 5, 40, 12)
    @app.open_window(win)
  end

  def press(x, y, kind: :press, button: :left)
    Rubbs::Modern::Widgets::Event.mouse(Rubbs::Common::Line::Telnet::MouseEvent.new(kind: kind, button: button, x: x, y: y))
  end

  def key(name) = Rubbs::Modern::Widgets::Event.key(name)

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
    button = Rubbs::Modern::Widgets::Button.new(label: '&Yes', on_click: ->(_) { pressed = true })
    button.layout(12, 8, 8, 1)
    win.add(button)
    win.reset_focus
    win.handle_event(key('y'))
    assert pressed
  end

  def test_an_unhandled_mouse_or_resize_event_is_ignored
    win = window
    win.add(Rubbs::Modern::Widgets::Button.new(label: '&Yes').tap { |b| b.layout(12, 8, 8, 1) })
    win.reset_focus
    assert_nil win.handle_event(press(30, 12, kind: :release))
    assert_nil win.handle_event(Rubbs::Modern::Widgets::Event.resize(80, 25))
  end

  def test_tab_moves_the_focus_between_buttons
    win = window
    a, b = %w[&A &B].map { |l| Rubbs::Modern::Widgets::Button.new(label: l).tap { |w| w.layout(12, 8, 6, 1) } }
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
    frame = Rubbs::Modern::FrameBuffer.new(80, 24)
    win.render(frame)
    screen = frame.diff(Rubbs::Modern::FrameBuffer.new(80, 24))
    %w[[■] Win [↑] ┘ ╔].each { |part| assert_includes screen, part }
  end
end

class StatusbarTest < Minitest::Test
  def bar
    bar = Rubbs::Modern::Statusbar.new(right_text: 'node 1')
    bar.add_hint('F1', 'Help') { :help }
    bar.add_hint('Alt-X', 'Bye') { nil }
    bar.add_hint('Q', 'Quit', hidden: true) { :quit }
    bar.layout(1, 24, 80, 1)
    bar.theme = Rubbs::Modern::Theme.mono
    bar
  end

  def test_keys_run_their_hints
    assert_equal :help, bar.handle_event(Rubbs::Modern::Widgets::Event.key(:f1))
    assert_equal :handled, bar.handle_event(Rubbs::Modern::Widgets::Event.key(:alt_x))
    assert_equal :quit, bar.handle_event(Rubbs::Modern::Widgets::Event.key('q'))
    assert_nil bar.handle_event(Rubbs::Modern::Widgets::Event.key(:f2))
  end

  def test_a_click_runs_the_shown_hint_under_it
    press = Rubbs::Common::Line::Telnet::MouseEvent.new(kind: :press, button: :left, x: 3, y: 24)
    click = Rubbs::Modern::Widgets::Event.mouse(press)
    assert_equal :help, bar.handle_event(click)
  end

  def test_render_shows_the_hints_and_the_right_text
    frame = Rubbs::Modern::FrameBuffer.new(80, 24)
    bar.render(frame)
    screen = frame.diff(Rubbs::Modern::FrameBuffer.new(80, 24))
    ['F1', ' Help ', 'node 1'].each { |part| assert_includes screen, part }
    refute_includes screen, 'Quit'
  end
end

class WindowSpecTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @app     = Rubbs::Modern::Application.new(session: @session, session_id: 's', services: { db: :the_db })
  end

  def teardown = @session.fake_line.close

  def test_a_form_runs_its_blocks_with_the_extras_and_the_services
    seen = nil
    spec = Rubbs::Modern::WindowSpec.new(:compose, :form) do
      title { "To #{who}" }
      prefill { { body: 'hello' } }
      field :body, label: 'Body'
      on_submit { |values| seen = [values[:body], db] }
    end
    form = spec.open(@app, who: 'ada')
    assert_equal 'To ada', form.title
    assert_equal :close, form.instance_variable_get(:@options)[:on_submit].call({ body: 'x' }, form)
    assert_equal ['x', :the_db], seen
  end

  def test_a_form_refusal_keeps_it_open_with_its_message
    spec = Rubbs::Modern::WindowSpec.new(:compose, :form) do
      field :body, label: 'Body'
      errors empty: 'Write something first.'
      on_submit { |values| values[:body].empty? ? :empty : :ok }
    end
    form = spec.open(@app)
    assert_equal :keep, form.instance_variable_get(:@options)[:on_submit].call({ body: '' }, form)
    assert_equal 'Write something first.', form.status_label.text
  end

  def test_an_extra_named_like_a_method_is_refused
    spec = Rubbs::Modern::WindowSpec.new(:list, :master_detail) { items { [] } }
    assert_raises(ArgumentError) { spec.open(@app, rows: 3) }
  end

  def test_a_master_detail_window_labels_and_wraps_in_the_app
    spec = Rubbs::Modern::WindowSpec.new(:list, :master_detail) do
      title 'List'
      items { %w[a b] }
      label { |item| "#{item}@#{db}" }
      detail { |item| ["#{item} #{'word ' * 40}"] }
    end
    win = spec.open(@app)
    assert_equal 'a@the_db', win.instance_variable_get(:@item_label).call('a')
    lines = win.instance_variable_get(:@render_detail).call('a', 30)
    assert_operator lines.size, :>, 1
    assert(lines.all? { |l| Rubbs::Modern::FrameBuffer.visible_width(l) <= 30 })
    assert win.maximizable
    assert_equal win, @app.window(:list)
  end

  def test_an_action_gets_the_selected_item_and_keeps_the_window
    taken = []
    spec = Rubbs::Modern::WindowSpec.new(:list, :master_detail) do
      items { %w[a b] }
      label :upcase
      action('Open') { |item| taken << item }
    end
    win = spec.open(@app)
    action = win.instance_variable_get(:@actions).first
    assert_equal :keep, action[:on_click].call(win)
    assert_equal ['a'], taken
    assert_equal '&Open', action[:label]
  end
end

class ApplicationTest < Minitest::Test
  def setup
    @session = FakeSession.new
  end

  def teardown = @session.fake_line.close

  def run_app(input, &)
    @session.fake_line.caller.write(input)
    app = Rubbs::Modern::Application.define(&).build(session: @session, session_id: 's')
    Timeout.timeout(5) { app.run }
    app
  end

  def test_a_status_key_that_halts_ends_the_run
    pressed = []
    run_app("\eOP\e[21~") do
      command(:help, 'Help', key: 'F1') { pressed << :help }
      command(:bye, 'Bye', key: 'F10') { log_off }
    end
    assert_equal [:help], pressed
    assert_includes @session.received, 'Help'
  end

  def test_the_line_dropping_ends_the_run
    @session.fake_line.caller.close
    app = Rubbs::Modern::Application.new(session: @session, session_id: 's')
    Timeout.timeout(5) { app.run }
    assert app.line_lost?
  end

  def test_f6_and_alt_digits_switch_windows
    app = Rubbs::Modern::Application.new(session: @session, session_id: 's')
    one, two = %w[One Two].map { |t| app.open_window(Rubbs::Modern::Window.new(title: t)) }
    assert_equal [1, 2], [one.number, two.number]
    app.send(:dispatch, Rubbs::Modern::Widgets::Event.key(:"alt_#{one.number}"))
    assert_same one, app.top_window
    app.send(:dispatch, Rubbs::Modern::Widgets::Event.key(:f6))
    assert_same two, app.top_window
  end

  def test_a_window_closing_itself_is_closed
    app = Rubbs::Modern::Application.new(session: @session, session_id: 's')
    closed = nil
    app.open_window(Rubbs::Modern::Window.new(title: 'W', on_close: ->(w) { closed = w }))
    app.send(:dispatch, Rubbs::Modern::Widgets::Event.key(:escape))
    assert_nil app.top_window
    refute_nil closed
  end

  def test_desktop_rect_leaves_the_bars
    app = Rubbs::Modern::Application.new(session: @session, session_id: 's')
    app.menubar = Rubbs::Modern::Menubar.new
    app.statusbar = Rubbs::Modern::Statusbar.new
    assert_equal [1, 2, 80, 22], app.desktop_rect
  end
end
