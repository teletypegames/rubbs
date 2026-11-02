# frozen_string_literal: true

require 'test_helper'

class DialogsTest < Minitest::Test
  FakeApp = Struct.new(:cols, :rows, :opened, :closed) do
    def open_window(window) = opened << window
    def close_window(window) = closed << window
  end

  def setup
    @app = FakeApp.new(80, 24, [], [])
  end

  def layout(window) = window.children.map { |c| [c.class.name.split('::').last, c.bounds.to_s] }

  def button(window, label) = window.children.find { |c| c.is_a?(BBS::Widgets::Button) && c.display_label == label }

  def test_message_wraps_and_centres
    window = BBS::Dialogs.message(@app, 'word ' * 15)
    assert_equal [window], @app.opened
    assert_equal '#13,9 55x7', window.bounds.to_s
    assert_equal [['Label', '#15,10 51x1'], ['Label', '#15,11 51x1'], ['Button', '#36,14 8x1']], layout(window)
    button(window, 'OK').fire
    assert_equal [window], @app.closed
  end

  def test_message_of_a_fixed_width_on_a_small_screen
    @app.cols = 30
    window = BBS::Dialogs.message(@app, 'hi', width: 40)
    assert_equal '#3,10 26x6', window.bounds.to_s
  end

  def test_confirm_calls_yes_or_no
    said = []
    window = BBS::Dialogs.confirm(@app, 'Sure?', on_yes: -> { said << :yes }, on_no: -> { said << :no })
    assert_equal [['Label', '#25,11 32x1'], ['Button', '#32,14 8x1'], ['Button', '#42,14 8x1']], layout(window)
    button(window, 'Yes').fire
    button(window, 'No').fire
    assert_equal %i[yes no], said
    assert_equal [window, window], @app.closed
  end

  def test_input_submits_the_text
    got = []
    window = BBS::Dialogs.input(@app, prompt: 'Name?', value: 'Ada', on_submit: ->(v) { got << v })
    field = window.children.find { |c| c.is_a?(BBS::Widgets::TextInput) }
    assert_equal [['Label', '#18,10 46x1'], ['TextInput', '#18,12 46x1'], ['Button', '#32,14 8x1'],
                  ['Button', '#42,14 10x1']], layout(window)
    assert_equal :handled, field.handle_event(BBS::Event.key(:enter))
    button(window, 'OK').fire
    button(window, 'Cancel').fire
    assert_equal %w[Ada Ada], got
    assert_equal 3, @app.closed.size
  end
end
