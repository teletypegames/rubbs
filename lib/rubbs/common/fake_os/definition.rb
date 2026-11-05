# frozen_string_literal: true

module Rubbs
  module Common
    module FakeOS
      # Immutable-ish description of one simulated OS, built via the define DSL.
      class Definition
        # Creates a definition named +OS+ with a <tt>'> '</tt> prompt, the
        # DEFAULT_COLORS, and no boot, ready or commands.
        def initialize
          @name        = 'OS'
          @prompt      = '> '
          @colors      = DEFAULT_COLORS.dup
          @boot_block  = nil
          @ready_block = nil
          @commands    = {}
          @order       = []
          @unknown     = nil
        end

        # Sets the OS name with an argument (<tt>name 'MS-DOS'</tt>); returns
        # it without one.
        def name(value = nil)
          value.nil? ? @name : (@name = value)
        end

        # Sets the shell prompt with a String argument, or with a block called
        # with the context before each line; returns it with neither.
        def prompt(value = nil, &block)
          if block then @prompt = block
          elsif !value.nil? then @prompt = value
          else @prompt
          end
        end

        # Merges overrides into the colour roles: each a colour name or an
        # xterm-256 index (Rubbs::Modern::Style, the text colour), a Hash of
        # Rubbs::Modern::Style.[] (<tt>{ fg: :green, faint: true }</tt>) or an SGR
        # String. Returns the colour Hash with no argument.
        #
        #   colors text: :green, accent: :bright_green, dim: { fg: :green, faint: true }
        def colors(overrides = nil)
          return @colors unless overrides

          @colors.merge!(overrides.transform_values { |value| Definition.sgr(value) })
        end

        # The SGR String of a colour given to #colors.
        def self.sgr(value)
          case value
          when String then value
          when Hash   then "#{Modern::Ansi::RESET}#{Modern::Style[**value]}"
          else "#{Modern::Ansi::RESET}#{Modern::Style[fg: value]}"
          end
        end

        # Sets the boot sequence, run in the Console before anything else.
        def boot(&block)  = (@boot_block = block)
        # Sets the block run in the Console once after boot, before the first
        # prompt.
        def ready(&block) = (@ready_block = block)

        # Registers a command under one or more names (the first is the
        # canonical one shown in help); names match case-insensitively. The
        # block receives <tt>(args_string, console)</tt>. +help+ is an optional
        # description stored with the command.
        def command(*names, help: nil, &block)
          primary = names.first.to_s
          @order << primary unless @order.include?(primary)
          names.each do |n|
            @commands[n.to_s.downcase] = { name: primary, help: help, block: block }
          end
        end

        # Sets the fallback for input that matches no command. The block gets
        # <tt>(input, console)</tt>. Without one, the shell prints "Bad command
        # or file name".
        def on_unknown(&block) = (@unknown = block)

        # The boot and ready blocks, the commands (a Hash of lower-case name to
        # a Hash with +:name+, +:help+ and +:block+), the canonical command
        # names in registration order, and the on_unknown block.
        attr_reader :boot_block, :ready_block, :commands, :order, :unknown
      end
    end
  end
end
