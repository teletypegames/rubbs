# frozen_string_literal: true

module Rubbs
  module Petscii
    class Screen
      # A few lines a caller fills one after the other (Screen#form): each
      # field a Screen#prompt.
      class Form
        # One field: the key of its answer, the +label+ before the line, a
        # +hint+ above it, the most characters (+max+), a +mask+ for a
        # password and whether the form needs it (+required+).
        Field = Data.define(:key, :label, :hint, :max, :mask, :required)

        # The fields declared so far, in order.
        attr_reader :fields

        # A form with the fields the block declares (#field), evaluated in it.
        def initialize(&)
          @fields = []
          instance_eval(&) if block_given?
        end

        # Declares the field +key+ asked as +label+ (the key's name when
        # +nil+). A field is required unless <tt>required: false</tt>.
        def field(key, label = nil, hint: nil, max: nil, mask: nil, required: true)
          @fields << Field.new(key: key, label: (label || key).to_s, hint: hint, max: max, mask: mask, required: required)
        end
      end

      # Asking a Form on a Screen.
      module Forms
        include Colors

        # Asks the fields the block declares (Form#field) one after the
        # other. Returns a Hash of each field's key and answer (stripped;
        # +nil+ for an optional field left empty), or +nil+ as soon as a
        # required one is left empty: the caller gave up.
        #
        #   site = screen.form do
        #     field :url, 'address', max: 80, hint: 'gopher:// or http://'
        #     field :name, 'name', max: 30, required: false
        #   end
        def form(&)
          Form.new(&).fields.each_with_object({}) do |f, answers|
            answers[f.key] = prompt(f.label, hint: f.hint, max: f.max, mask: f.mask)
            return nil if f.required && answers[f.key].nil?
          end
        end

        # Tells the caller +text+ in cyan, a piece of information, and waits
        # for a key.
        def info(text)
          puts
          say(text, color: CY)
          pause
        end
      end

      include Forms
    end
  end
end
