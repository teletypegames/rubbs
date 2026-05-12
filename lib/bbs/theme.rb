# frozen_string_literal: true

module BBS
  # A Theme maps named style roles (e.g. :window_border, :button_focused)
  # to ANSI SGR sequences. Widgets fetch styles via Widget#style(key).
  #
  # Two presets are provided:
  #   Theme.synchronet — yellow/cyan Synchronet-inspired palette
  #   Theme.mono       — black & white, for terminals without color
  class Theme
    attr_reader :styles, :name

    def initialize(name, styles)
      @name   = name
      @styles = styles
    end

    def style(key)        = @styles[key]
    def [](key)           = @styles[key]
    def merge(overrides)  = Theme.new(@name, @styles.merge(overrides))

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

        reset:            "\e[0m",
      }.freeze).freeze
    end

    def self.mono
      Theme.new(:mono, {
        screen:           "",
        text:             "\e[0;37m",
        text_dim:         "\e[0;2;37m",
        text_bright:      "\e[1;37m",
        label:            "\e[0;37m",
        accent:           "\e[1;37m",
        success:          "\e[1;37m",
        warning:          "\e[1;37m",
        error:            "\e[7m",
        window_bg:        "",
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
        reset:            "\e[0m",
      }.freeze).freeze
    end
  end
end
