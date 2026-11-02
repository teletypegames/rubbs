# frozen_string_literal: true

require_relative 'theme/presets'

module BBS
  # A Theme maps the style ROLES (such as +:window_border+ or
  # +:button_focused+) to ANSI SGR sequences. Widgets fetch styles through
  # Widget#style.
  #
  # The presets are data, a Hash each in PRESETS:
  #
  # [+:synchronet+]      white and yellow on blue windows over a black
  #                      screen, after Synchronet
  # [+:nortoncommander+] cyan and blue panels, after Norton Commander
  # [+:dosnavigator+]    black on light grey with cyan bars, after DOS
  #                      Navigator
  # [+:neumanntronics+]  teal and amber on black in 256 colours
  # [+:mono+]            no colour, only bold, dim, underline and
  #                      reverse, for terminals without colour
  #
  # ::fetch builds one; derive a variant with #merge:
  #
  #   BBS::Theme.fetch(:synchronet).merge(window_bg: "\e[41m")
  class Theme
    # The style roles every preset defines and a theme may set.
    ROLES = PRESETS.fetch(:synchronet).keys.freeze

    # The style Hash (role Symbol => SGR String) and the theme's name Symbol.
    attr_reader :styles, :name

    # Returns the preset called +name+ (a Symbol or String key of PRESETS),
    # or +name+ itself when it is a Theme already. Raises ArgumentError
    # ("unknown theme") for any other name.
    #
    #   BBS::Theme.fetch(:dosnavigator)   # => the DOS Navigator preset
    def self.fetch(name)
      return name if name.is_a?(Theme)

      styles = PRESETS.fetch(name.to_s.to_sym) { raise ArgumentError, "unknown theme: #{name.inspect}" }
      new(name.to_sym, styles)
    end

    # The style roles, ROLES.
    def self.roles = ROLES

    # The +:synchronet+ preset (see ::fetch).
    def self.synchronet = fetch(:synchronet)
    # The +:nortoncommander+ preset (see ::fetch).
    def self.nortoncommander = fetch(:nortoncommander)
    # The +:dosnavigator+ preset (see ::fetch).
    def self.dosnavigator = fetch(:dosnavigator)
    # The +:neumanntronics+ preset (see ::fetch).
    def self.neumanntronics = fetch(:neumanntronics)
    # The +:mono+ preset (see ::fetch).
    def self.mono = fetch(:mono)

    # Creates a theme called +name+ from +styles+, a Hash of role Symbols
    # (of ROLES) to SGR Strings. Raises ArgumentError for a role not in
    # ROLES.
    def initialize(name, styles)
      unknown = styles.keys - ROLES
      raise ArgumentError, "unknown theme roles: #{unknown.inspect}" unless unknown.empty?

      @name   = name
      @styles = styles.frozen? ? styles : styles.dup.freeze
      freeze
    end

    # Returns the SGR String for the role +key+, or +nil+ when the theme
    # does not define it.
    def [](key) = @styles[key]

    # Same as #[].
    def style(key) = @styles[key]

    # Returns a new Theme with the same name and the roles in the Hash
    # +overrides+ replacing this theme's styles. Raises ArgumentError for
    # a role not in ROLES.
    def merge(overrides) = Theme.new(@name, @styles.merge(overrides))
  end
end
