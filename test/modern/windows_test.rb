# frozen_string_literal: true

require 'test_helper'

class WindowsTest < Minitest::Test
  def setup
    @session = FakeSession.new
    @app     = Rubbs::Modern::Application::Builder.new.build(session: @session, session_id: 's')
  end

  def teardown = @session.fake_line.close

  def labels(window) = window.children.grep(Rubbs::Modern::Widgets::Label).map(&:text)

  def test_form_values_status_and_layout
    form = Rubbs::Modern::Windows::Form.open(
      @app,
      title:     ' F ',
      hint:      'Fill it in.',
      on_submit: nil,
      fields:    [{ key: :name, label: 'Name', value: 'Ada' },
                  { key: :ok, label: 'OK?', type: :checkbox, value: true },
                  { key: :notes, type: :textarea, value: "a\nb", rows: 3 }]
    )
    assert_equal({ name: 'Ada', ok: true, notes: "a\nb" }, form.values)
    form.error('Bad.')
    assert_equal ['Bad.', :error], [form.status_label.text, form.status_label.style_key]
    assert_equal 16, form.bounds.height
    assert_includes labels(form), 'Fill it in.'
  end

  def test_form_refuses_an_unknown_option
    assert_raises(ArgumentError) { Rubbs::Modern::Windows::Form.new(app: @app, title: 'x', fields: [], colour: 1) }
  end

  def test_form_submit_gets_the_values
    got = nil
    form = Rubbs::Modern::Windows::Form.open(
      @app,
      title:     'x',
      fields:    [{ key: :a, value: 'v' }],
      on_submit: ->(values, _f) { got = values }
    )
    form.children.grep(Rubbs::Modern::Widgets::Button).first.on_click.call(nil)
    assert_equal({ a: 'v' }, got)
  end

  def test_button_bar_aligns_left_right_and_centre
    win = Rubbs::Modern::Window.new(title: 'w')
    win.layout(1, 1, 40, 10)
    bar = Rubbs::Modern::Windows::ButtonBar.attach(win, @app, [{ key: :l, label: 'L', align: :left },
                                                               { key: :r, label: 'R', primary: true }])
    assert_equal [3, 9], [bar[:by_key][:l].bounds.x, bar[:by_key][:l].bounds.y]
    assert_equal 40 - 5, bar[:by_key][:r].bounds.x
    assert_same bar[:by_key][:r], bar[:primary]
    one = Rubbs::Modern::Windows::ButtonBar.attach(win, @app, [{ label: 'C' }])
    assert_equal 1 + ((40 - 5) / 2), one[:widgets].first.bounds.x
  end

  def test_info_static_body_kinds
    info = Rubbs::Modern::Windows::Info.open(
      @app,
      title: 'i',
      width: 40,
      body:  ['plain', :spacer, :rule, { text: 'styled', style: :accent },
              { kv: [%w[Key value]] }]
    )
    assert_includes labels(info), 'plain'
    assert_includes labels(info), 'Key     '
    assert_includes labels(info), 'value'
    assert_equal 1 + 5 + 2 + 2, info.bounds.height
  end

  def test_info_scroll_body_lines
    info = Rubbs::Modern::Windows::Info.open(@app, title: 'i', scroll: true, body: ['one', nil, { kv: [%w[k v]] }])
    t = @app.theme
    assert_equal ['one', '', "#{t[:input_label]}k       #{t[:text]}  v"], info.scroll_view.lines
    assert_raises(ArgumentError) do
      Rubbs::Modern::Windows::Info.new(app: @app, title: 'i', scroll: true, body: [Rubbs::Modern::Widgets::Label.new(text: 'x')])
    end
  end

  def test_master_detail_renders_the_selected_item
    md = Rubbs::Modern::Windows::MasterDetail.open(
      @app,
      title:         'm',
      items:         %w[a b],
      item_label:    :upcase.to_proc,
      render_detail: ->(item, _w) { ["detail #{item}"] },
      bottom_meta:   ->(item) { "meta #{item}" }
    )
    assert_equal ['detail a'], md.detail_view.lines
    assert_equal 'meta a', md.meta_label.text
    md.replace_items([])
    assert_equal ['  (empty)'], md.detail_view.lines
    assert_equal '', md.meta_label.text
  end

  def test_stream_keeps_the_buffer_and_submits
    sent = []
    stream = Rubbs::Modern::Windows::Stream.open(
      @app,
      title:         's',
      buffer_size:   2,
      initial_lines: ['x'],
      on_poll:       ->(_a) { %w[y z] },
      on_submit:     ->(text, _a) { sent << text }
    )
    stream.tick(@app)
    assert_equal %w[y z], stream.history.lines
    stream.input.value = 'hi'
    stream.input.on_submit.call('hi', stream.input)
    assert_equal ['hi'], sent
    assert_equal '', stream.input.value
  end
end
