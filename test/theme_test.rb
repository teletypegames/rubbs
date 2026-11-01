# frozen_string_literal: true

require 'test_helper'

class ThemeTest < Minitest::Test
  def test_fetch
    assert_equal :dosnavigator, BBS::Theme.fetch(:dosnavigator).name
    assert_equal :mono, BBS::Theme.fetch('mono').name
    theme = BBS::Theme.synchronet
    assert_same theme, BBS::Theme.fetch(theme)
    assert_raises(ArgumentError) { BBS::Theme.fetch(:instance_method) }
    assert_raises(ArgumentError) { BBS::Theme.fetch(:new) }
  end

  def test_builder_theme
    builder = BBS::Application::Builder.new
    assert_nil builder.theme
    builder.theme(:mono)
    assert_equal :mono, builder.theme.name
    builder.theme(:synchronet) { screen 'X' }
    assert_equal 'X', builder.theme[:screen]
    assert_raises(ArgumentError) { builder.theme(:nope) }
  end

  def test_theme_builder_takes_known_roles_only
    builder = BBS::Application::ThemeBuilder.new(BBS::Theme.mono)
    builder.window_bg 'B'
    assert builder.respond_to?(:window_bg)
    refute builder.respond_to?(:windw_bg)
    assert_raises(NoMethodError) { builder.windw_bg 'B' }
    assert_raises(ArgumentError) { builder.inherit(:nope) }
    assert_equal 'B', builder.build[:window_bg]
  end

  def test_services_are_frozen_per_application
    builder = BBS::Application::Builder.new
    builder.services(db: :x)
    app = builder.build(session: FakeSession.new, session_id: 's')
    assert app.services.frozen?
    refute builder.services.frozen?
  end
end
