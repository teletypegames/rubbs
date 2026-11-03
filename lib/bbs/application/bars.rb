# frozen_string_literal: true

module BBS
  class Application
    class Builder
      # How a Builder makes the menubar (its menus and the Help menu) and the
      # statusbar (a hint per command with a key) of an application.
      module Bars
        # The width of the Help menu's message boxes and its Keys page.
        HELP_WIDTH = 72

        private

        def build_menubar(app)
          menubar = Menubar.new
          menubar.theme = app.theme
          @menus.each { |label, entries, block| add_menu(menubar, app, label, entries, block) }
          add_help(menubar, app) if @help
          menubar
        end

        def add_menu(menubar, app, label, entries, block)
          items = ItemsBuilder.new(app, all_commands)
          entries.each { |entry| items.entry(entry) }
          items.instance_eval(&block) if block
          menubar.menus << Menubar::Menu.new(label: Command.hotkeyed(label, []), items: items.items, x: nil)
        end

        def add_help(menubar, app)
          items = ItemsBuilder.new(app, all_commands)
          items.instance_eval(&@help[:items]) if @help[:items]
          help_pages.each { |title, text| add_page(items, title, text) }
          keys = Command.keys_page(all_commands.values, @help[:keys])
          items.item('Keys') { BBS::Windows::Info.open(self, title: 'Keys', body: keys, width: HELP_WIDTH) }
          menubar.menus << Menubar::Menu.new(label: '&Help', items: items.items, x: nil)
        end

        def add_page(items, title, text)
          items.item(title) { message(text.respond_to?(:call) ? instance_exec(&text) : text, title: title, width: HELP_WIDTH) }
        end

        def help_pages
          pages = @help[:pages].transform_keys { |name| name.is_a?(String) ? name : name.to_s.tr('_', ' ').capitalize }
          @help[:about] ? { 'About' => @help[:about], **pages } : pages
        end

        def build_statusbar(app)
          statusbar = Statusbar.new
          statusbar.theme = app.theme
          all_commands.each_value do |command|
            next unless command.key

            statusbar.add_hint(command.key, command.hint_text, hidden: command.hint == false) { command.run(app) }
          end
          statusbar
        end
      end
    end
  end
end
