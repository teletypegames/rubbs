# frozen_string_literal: true

require 'test_helper'

class ThemeTest < Minitest::Test
  def test_fetch
    assert_equal :dosnavigator, Rubbs::Modern::Theme.fetch(:dosnavigator).name
    assert_equal :mono, Rubbs::Modern::Theme.fetch('mono').name
    theme = Rubbs::Modern::Theme.synchronet
    assert_same theme, Rubbs::Modern::Theme.fetch(theme)
    assert_raises(ArgumentError) { Rubbs::Modern::Theme.fetch(:instance_method) }
    assert_raises(ArgumentError) { Rubbs::Modern::Theme.fetch(:new) }
  end

  def test_builder_theme
    builder = Rubbs::Modern::Application::Builder.new
    assert_nil builder.theme
    builder.theme(:mono)
    assert_equal :mono, builder.theme.name
    builder.theme(:synchronet) { screen 'X' }
    assert_equal 'X', builder.theme[:screen]
    assert_raises(ArgumentError) { builder.theme(:nope) }
  end

  def test_theme_builder_takes_known_roles_only
    builder = Rubbs::Modern::Application::ThemeBuilder.new(Rubbs::Modern::Theme.mono)
    builder.window_bg 'B'
    assert builder.respond_to?(:window_bg)
    refute builder.respond_to?(:windw_bg)
    assert_raises(NoMethodError) { builder.windw_bg 'B' }
    assert_raises(ArgumentError) { builder.inherit(:nope) }
    assert_equal 'B', builder.build[:window_bg]
  end

  def test_services_are_frozen_per_application
    builder = Rubbs::Modern::Application::Builder.new
    builder.services(db: :x)
    app = builder.build(session: FakeSession.new, session_id: 's')
    assert app.services.frozen?
    refute builder.services.frozen?
  end
end

class ThemePresetsTest < Minitest::Test
  def test_every_preset_defines_every_role
    Rubbs::Modern::Theme::PRESETS.each do |name, styles|
      assert_equal Rubbs::Modern::Theme::ROLES.sort, styles.keys.sort, "#{name} roles"
    end
  end

  def test_an_unknown_role_is_refused
    assert_raises(ArgumentError) { Rubbs::Modern::Theme.synchronet.merge(windw_bg: 'x') }
  end

  def test_merge_keeps_the_name_and_replaces_a_role
    theme = Rubbs::Modern::Theme.mono.merge(window_bg: 'B')
    assert_equal [:mono, 'B'], [theme.name, theme[:window_bg]]
  end
end
