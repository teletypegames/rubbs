# frozen_string_literal: true

module BBS
  # A Theme maps named style roles (such as +:window_border+ or
  # +:button_focused+) to ANSI SGR sequences. Widgets fetch styles through
  # Widget#style.
  #
  # Five presets are provided:
  #
  # [Theme.synchronet]      white and yellow on blue windows over a black
  #                         screen, after Synchronet
  # [Theme.nortoncommander] cyan and blue panels, after Norton Commander
  # [Theme.dosnavigator]    black on light grey with cyan bars, after DOS
  #                         Navigator
  # [Theme.neumanntronics]  teal and amber on black in 256 colours
  # [Theme.mono]            no colour, only bold, dim, underline and
  #                         reverse, for terminals without colour
  #
  # Derive a variant with #merge:
  #
  #   BBS::Theme.synchronet.merge(window_bg: "\e[41m")
  class Theme
    # The names of the presets, each a class method returning its Theme.
    PRESETS = %i[synchronet nortoncommander dosnavigator neumanntronics mono].freeze

    # The style Hash (role Symbol => SGR String) and the theme's name Symbol.
    attr_reader :styles, :name

    # Returns the preset called +name+ (a Symbol or String from PRESETS), or
    # +name+ itself when it is a Theme already. Raises ArgumentError
    # ("unknown theme") for any other name.
    #
    #   BBS::Theme.fetch(:dosnavigator)   # => the DOS Navigator preset
    def self.fetch(name)
      return name if name.is_a?(Theme)
      raise ArgumentError, "unknown theme: #{name.inspect}" unless PRESETS.include?(name.to_s.to_sym)

      public_send(name.to_sym)
    end

    # Returns the names of the style roles any preset defines, an Array of
    # Symbol.
    def self.roles = @roles ||= PRESETS.flat_map { |preset| fetch(preset).styles.keys }.uniq.freeze

    # Creates a theme called +name+ from +styles+, a Hash of role Symbols to
    # SGR Strings.
    def initialize(name, styles)
      @name   = name
      @styles = styles
    end

    # Returns the SGR String for the role +key+, or +nil+ when the theme
    # does not define it.
    def style(key)        = @styles[key]
    # Same as #style.
    def [](key)           = @styles[key]
    # Returns a new Theme with the same name and the roles in the Hash
    # +overrides+ replacing or adding to this theme's styles.
    def merge(overrides)  = Theme.new(@name, @styles.merge(overrides))

    # Returns the +:synchronet+ preset: white and yellow on blue windows
    # over a black screen, light grey menu and status bars.
    def self.synchronet
      Theme.new(:synchronet, {
        screen:           "\e[40m",
        text:             "\e[0;37;40m",
        text_dim:         "\e[0;2;37;40m",
        text_bright:      "\e[1;37;40m",
        label:            "\e[0;36;40m",
        accent:           "\e[1;33;40m",
        success:          "\e[1;32;40m",
        warning:          "\e[1;33;40m",
        error:            "\e[1;31;40m",

        window_bg:        "\e[44m",
        window_border:    "\e[1;37;44m",
        window_title:     "\e[1;33;44m",
        window_title_focused: "\e[1;30;47m",
        window_text:      "\e[0;37;44m",
        window_shadow:    "\e[40m",

        menubar:          "\e[1;30;47m",
        menubar_hotkey:   "\e[1;31;47m",
        menubar_selected: "\e[1;37;42m",
        menubar_sel_hot:  "\e[1;33;42m",

        menu_bg:          "\e[1;37;44m",
        menu_text:        "\e[0;37;44m",
        menu_hotkey:      "\e[1;33;44m",
        menu_selected:    "\e[1;37;46m",
        menu_disabled:    "\e[0;2;37;44m",
        menu_border:      "\e[1;37;44m",

        statusbar:        "\e[1;30;47m",
        statusbar_key:    "\e[1;31;47m",

        button:           "\e[0;30;47m",
        button_focused:   "\e[1;37;42m",
        button_hotkey:    "\e[1;31;47m",
        button_disabled:  "\e[0;2;30;47m",

        input:            "\e[1;37;44m",
        input_focused:    "\e[1;30;47m",
        input_label:      "\e[0;36;40m",

        listbox:          "\e[0;37;44m",
        listbox_selected: "\e[1;37;46m",
        listbox_focused:  "\e[1;30;47m",
        listbox_header:   "\e[1;33;44m",

        scrollbar:        "\e[0;36;44m",
        scrollbar_thumb:  "\e[1;37;46m",

        check_on:         "\e[1;32;44m",
        check_off:        "\e[0;37;44m",

        reset:            "\e[0m"
      }.freeze).freeze
    end

    # Returns the +:nortoncommander+ preset: a blue screen with cyan borders
    # and bars and light grey menus. Defines no +:check_on+/+:check_off+.
    def self.nortoncommander
      Theme.new(:nortoncommander, {
        screen:           "\e[44m",
        text:             "\e[0;37;44m",
        text_dim:         "\e[0;2;37;44m",
        text_bright:      "\e[1;37;44m",
        label:            "\e[0;36;44m",
        accent:           "\e[1;33;44m",
        success:          "\e[1;32;44m",
        warning:          "\e[1;33;44m",
        error:            "\e[1;31;44m",

        window_bg:        "\e[44m",
        window_border:    "\e[1;36;44m",
        window_title:     "\e[1;30;46m",
        window_title_focused: "\e[1;37;46m",
        window_text:      "\e[0;37;44m",
        window_shadow:    "\e[40m",

        menubar:          "\e[1;30;46m",
        menubar_hotkey:   "\e[1;31;46m",
        menubar_selected: "\e[1;30;42m",
        menubar_sel_hot:  "\e[1;31;42m",

        menu_bg:          "\e[1;30;47m",
        menu_text:        "\e[1;30;47m",
        menu_hotkey:      "\e[1;31;47m",
        menu_selected:    "\e[1;37;42m",
        menu_disabled:    "\e[0;2;30;47m",
        menu_border:      "\e[1;30;47m",

        statusbar:        "\e[1;30;46m",
        statusbar_key:    "\e[1;33;46m",

        button:           "\e[1;37;42m",
        button_focused:   "\e[1;37;46m",
        button_hotkey:    "\e[1;33;42m",
        button_disabled:  "\e[0;2;37;42m",

        input:            "\e[1;30;46m",
        input_focused:    "\e[1;37;46m",
        input_label:      "\e[1;33;44m",

        listbox:          "\e[0;37;44m",
        listbox_selected: "\e[1;37;46m",
        listbox_focused:  "\e[0;30;46m",
        listbox_header:   "\e[1;33;44m",

        scrollbar:        "\e[0;36;44m",
        scrollbar_thumb:  "\e[1;37;46m",

        reset:            "\e[0m"
      }.freeze).freeze
    end

    # Returns the +:dosnavigator+ preset: black on light grey with cyan bars
    # and green selections. Defines no +:check_on+/+:check_off+.
    def self.dosnavigator
      Theme.new(:dosnavigator, {
        screen:           "\e[47m",
        text:             "\e[0;30;47m",
        text_dim:         "\e[0;2;30;47m",
        text_bright:      "\e[1;30;47m",
        label:            "\e[0;30;47m",
        accent:           "\e[0;34;47m",
        success:          "\e[0;32;47m",
        warning:          "\e[0;31;47m",
        error:            "\e[1;31;47m",

        window_bg:        "\e[47m",
        window_border:    "\e[0;30;47m",
        window_title:     "\e[0;30;46m",
        window_title_focused: "\e[1;37;46m",
        window_text:      "\e[0;30;47m",
        window_shadow:    "\e[40m",

        menubar:          "\e[0;30;46m",
        menubar_hotkey:   "\e[1;31;46m",
        menubar_selected: "\e[1;37;42m",
        menubar_sel_hot:  "\e[1;33;42m",

        menu_bg:          "\e[0;30;47m",
        menu_text:        "\e[0;30;47m",
        menu_hotkey:      "\e[1;31;47m",
        menu_selected:    "\e[1;37;42m",
        menu_disabled:    "\e[0;2;30;47m",
        menu_border:      "\e[0;30;47m",

        statusbar:        "\e[0;30;46m",
        statusbar_key:    "\e[1;33;46m",

        button:           "\e[0;30;47m",
        button_focused:   "\e[1;37;42m",
        button_hotkey:    "\e[1;31;47m",
        button_disabled:  "\e[0;2;30;47m",

        input:            "\e[0;30;47m",
        input_focused:    "\e[1;30;46m",
        input_label:      "\e[0;30;47m",

        listbox:          "\e[0;30;47m",
        listbox_selected: "\e[0;30;46m",
        listbox_focused:  "\e[1;37;46m",
        listbox_header:   "\e[0;30;46m",

        scrollbar:        "\e[0;30;47m",
        scrollbar_thumb:  "\e[1;37;46m",

        reset:            "\e[0m"
      }.freeze).freeze
    end

    # Returns the +:neumanntronics+ preset: teal and amber on black, using
    # 256-colour SGR codes.
    def self.neumanntronics
      Theme.new(:neumanntronics, {
        screen:           "\e[48;5;16m",
        text:             "\e[0;38;5;73;48;5;16m",
        text_dim:         "\e[0;38;5;66;48;5;16m",
        text_bright:      "\e[0;38;5;116;48;5;16m",
        label:            "\e[0;38;5;73;48;5;16m",
        accent:           "\e[0;38;5;220;48;5;16m",
        success:          "\e[0;38;5;79;48;5;16m",
        warning:          "\e[0;38;5;220;48;5;16m",
        error:            "\e[0;38;5;203;48;5;16m",

        window_bg:        "\e[48;5;16m",
        window_border:    "\e[0;38;5;73;48;5;16m",
        window_title:     "\e[0;38;5;116;48;5;23m",
        window_title_focused: "\e[0;38;5;220;48;5;23m",
        window_text:      "\e[0;38;5;73;48;5;16m",
        window_shadow:    "\e[48;5;16m",

        menubar:          "\e[0;38;5;116;48;5;23m",
        menubar_hotkey:   "\e[0;38;5;220;48;5;23m",
        menubar_selected: "\e[0;38;5;16;48;5;73m",
        menubar_sel_hot:  "\e[0;38;5;16;48;5;220m",

        menu_bg:          "\e[0;38;5;73;48;5;23m",
        menu_text:        "\e[0;38;5;73;48;5;23m",
        menu_hotkey:      "\e[0;38;5;220;48;5;23m",
        menu_selected:    "\e[0;38;5;16;48;5;73m",
        menu_disabled:    "\e[0;38;5;66;48;5;23m",
        menu_border:      "\e[0;38;5;73;48;5;23m",

        statusbar:        "\e[0;38;5;116;48;5;23m",
        statusbar_key:    "\e[0;38;5;220;48;5;23m",

        button:           "\e[0;38;5;73;48;5;16m",
        button_focused:   "\e[0;38;5;16;48;5;73m",
        button_hotkey:    "\e[0;38;5;220;48;5;16m",
        button_disabled:  "\e[0;38;5;66;48;5;16m",

        input:            "\e[0;38;5;73;48;5;16m",
        input_focused:    "\e[0;38;5;16;48;5;73m",
        input_label:      "\e[0;38;5;73;48;5;16m",

        listbox:          "\e[0;38;5;73;48;5;16m",
        listbox_selected: "\e[0;38;5;16;48;5;73m",
        listbox_focused:  "\e[0;38;5;220;48;5;16m",
        listbox_header:   "\e[0;38;5;116;48;5;23m",

        scrollbar:        "\e[0;38;5;66;48;5;16m",
        scrollbar_thumb:  "\e[0;38;5;73;48;5;16m",

        check_on:         "\e[0;38;5;220;48;5;16m",
        check_off:        "\e[0;38;5;73;48;5;16m",

        reset:            "\e[0m"
      }.freeze).freeze
    end

    # Returns the +:mono+ preset: no colour, only bold, dim, underline and
    # reverse video, for terminals without colour.
    def self.mono
      Theme.new(:mono, {
        screen:           '',
        text:             "\e[0;37m",
        text_dim:         "\e[0;2;37m",
        text_bright:      "\e[1;37m",
        label:            "\e[0;37m",
        accent:           "\e[1;37m",
        success:          "\e[1;37m",
        warning:          "\e[1;37m",
        error:            "\e[7m",
        window_bg:        '',
        window_border:    "\e[1;37m",
        window_title:     "\e[1;37m",
        window_title_focused: "\e[7m",
        window_text:      "\e[0;37m",
        window_shadow:    "\e[2;37m",
        menubar:          "\e[7m",
        menubar_hotkey:   "\e[1;7m",
        menubar_selected: "\e[1m",
        menubar_sel_hot:  "\e[1;4m",
        menu_bg:          "\e[7m",
        menu_text:        "\e[7m",
        menu_hotkey:      "\e[1;7m",
        menu_selected:    "\e[1;4m",
        menu_disabled:    "\e[2;7m",
        menu_border:      "\e[7m",
        statusbar:        "\e[7m",
        statusbar_key:    "\e[1;4;7m",
        button:           "\e[7m",
        button_focused:   "\e[1;4;7m",
        button_hotkey:    "\e[1;4;7m",
        button_disabled:  "\e[2;7m",
        input:            "\e[4m",
        input_focused:    "\e[1;4m",
        input_label:      "\e[0;37m",
        listbox:          "\e[0;37m",
        listbox_selected: "\e[7m",
        listbox_focused:  "\e[1;7m",
        listbox_header:   "\e[1;4m",
        scrollbar:        "\e[2;37m",
        scrollbar_thumb:  "\e[1;37m",
        check_on:         "\e[1;7m",
        check_off:        "\e[0;37m",
        reset:            "\e[0m"
      }.freeze).freeze
    end
  end
end
