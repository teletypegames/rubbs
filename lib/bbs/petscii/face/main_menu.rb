# frozen_string_literal: true

module BBS
  module Petscii
    class Face
      # The main menu of a Face: items with a key, a label and an about
      # line, each running its block in the face.
      class MainMenu
        include Colors

        # One entry: +key+, +label+ (a String or a block evaluated in the
        # face), +about+, the +action+ block, and whether it is a +heading+.
        Entry = Struct.new(:key, :label, :about, :action, :heading, :color, :shown, keyword_init: true)

        # Evaluates the declarations of the block; +hint+ is the hint row,
        # +back+ the key ← takes (+nil+: log off), +home+ what is drawn above
        # the menu each round (+:title+, the home title bar, or +:masthead+),
        # +above+ a block whose lines (evaluated in the face) come between
        # that and the menu.
        def initialize(hint, back = nil, home: :title, above: nil, &)
          @hint    = hint
          @back    = back || :log_off
          @home    = home
          @above   = above
          @entries = []
          instance_eval(&)
        end

        # An item: +key+ takes it, +label+ names it (a block for a label
        # that changes), +about+ is shown while it is lit (a block too); the block runs in
        # the face. An item without a block only goes back to the caller of
        # Face#main_menu_choice (returning its key).
        #
        # +if+ is a block (evaluated in the face) that hides the item when it
        # answers false.
        def item(key, label, about = nil, color: nil, if: nil, &action)
          @entries << Entry.new(key: key, label: label, about: about, action: action, color: color,
                                shown: binding.local_variable_get(:if))
        end

        # Items made each round from what the block +source+ gives (evaluated
        # in the face): +build+ is called in this menu with each object and
        # its index, and declares the items for it with #item.
        #
        #   each_of(-> { catalog.shelves }) { |shelf, i| item((i + 1).to_s, shelf.name) { open_shelf(shelf) } }
        def each_of(source, &build)
          @entries << Entry.new(action: [source, build], heading: :dynamic)
        end

        # A heading above the items under it (or an empty line).
        def heading(label = '') = @entries << Entry.new(label: label, heading: true)

        # The declared entries (after #each_of, the ones it made).
        attr_reader :entries

        # The item that logs off (key +q+).
        def log_off(about = 'hang up. see you!', label: 'log off', key: 'q')
          @entries << Entry.new(key: key, label: label, about: about, action: :log_off)
        end

        # Shows the menu on +face+ and runs the taken item. Returns
        # +:log_off+ for the log-off item and ← (RUN/STOP), the item's key
        # for an item without a block, else +nil+.
        def take(face)
          draw_home(face)
          entries = expand(face)
          picked  = face.menu(items(face, entries), index: index_of(entries, face.menu_cursor), back: @back,
                                                    hint: @hint)
          face.menu_cursor = picked
          run(face, entries, picked)
        end

        private

        def draw_home(face)
          if face.masthead_up?
            face.masthead_up = false
          elsif @home == :masthead
            face.show_masthead
            face.masthead_up = false
          else
            face.home
          end
          Array(@above && face.instance_exec(&@above)).each { |line| face.puts(line) }
          face.puts
        end

        def expand(face)
          made = @entries.flat_map { |e| e.heading == :dynamic ? made_by(face, *e.action) : [e] }
          made.select { |e| e.shown.nil? || face.instance_exec(&e.shown) }
        end

        def made_by(face, source, build)
          menu = MainMenu.new(@hint) { nil }
          Array(face.instance_exec(&source)).each_with_index { |object, i| menu.instance_exec(object, i, &build) }
          menu.entries
        end

        def items(face, entries)
          entries.map do |e|
            next Selector.heading(e.label) if e.heading

            label, about = [e.label, e.about].map { |v| v.respond_to?(:call) ? face.instance_exec(&v) : v }
            Selector.item(label.to_s, key: e.key, value: e.key, about: about, color: e.color)
          end
        end

        def index_of(entries, key) = key && entries.index { |e| !e.heading && e.key == key }

        def run(face, entries, key)
          entry = entries.find { |e| !e.heading && e.key == key }
          return :log_off if key == :log_off || entry.nil? || entry.action == :log_off
          return key unless entry.action

          face.instance_exec(&entry.action)
          nil
        end
      end
    end
  end
end
