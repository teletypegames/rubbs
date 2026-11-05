# frozen_string_literal: true

require_relative 'text/banner'

module Rubbs
  module Common
    # A configurable, teletype-style character-mode OS simulator: a scripted
    # boot sequence followed by an interactive command shell. Each simulated OS
    # (MS-DOS, CP/M, an AmigaDOS CLI, …) is just a different Definition — the
    # engine here is generic, so new "operating systems" are added as config,
    # not as new code.
    #
    #   DOS = Rubbs::Common::FakeOS.define do
    #     name   'MS-DOS'
    #     prompt 'C:\\>'
    #     colors text: "\e[0;37m", accent: "\e[1;32m"
    #
    #     boot do
    #       print 'Award Modular BIOS v4.51PG', delay: 0.4
    #       memtest 16_384
    #       pause 0.5
    #       cls
    #       big_banner 'MS-DOS'
    #     end
    #
    #     ready { puts 'Type HELP for a list of commands.' }
    #
    #     command 'ver'          { |_args, io| io.puts 'MS-DOS Version 6.22' }
    #     command 'cls'          { |_args, io| io.cls }
    #     command 'exit', 'quit' { |_args, io| io.halt }
    #
    #     on_unknown do |input, io|
    #       io.puts "Bad command or file name"
    #     end
    #   end
    #
    #   Rubbs::Common::FakeOS::Runner.new(session, DOS).run
    #
    # The boot/ready blocks run against a Console (so primitives like +print+,
    # +cls+, +pause+, +banner+, +type+ are available without a receiver).
    # Command and on_unknown blocks are called with
    # <tt>(args_or_input, console)</tt>; use the console (+io+) for all output.
    # +on_unknown+ is the natural hook for a conversational / LLM-backed shell:
    # anything that is not a registered command lands there.
    module FakeOS
      # The default SGR sequence for each colour role a Console uses: +text+,
      # +bright+, +accent+, +error+, +dim+, +prompt+, and +base+, which every
      # reset returns to.
      DEFAULT_COLORS = {
        text:   Modern::Ansi::GREY, # light grey on black — the classic console look
        bright: Modern::Ansi::WHITE,
        accent: Modern::Ansi::BRIGHT_GREEN,
        error:  Modern::Ansi::BRIGHT_RED,
        dim:    Modern::Ansi::DARK_GREY,
        prompt: Modern::Ansi::GREY,
        base:   '' # what every reset returns to: a background here colours the whole screen
      }.freeze

      # Builds a Definition by evaluating the block in a new one.
      #
      # Returns the Definition.
      def self.define(&)
        definition = Definition.new
        definition.instance_eval(&)
        definition
      end
    end
  end
end

require_relative 'fake_os/definition'
require_relative 'fake_os/console'
require_relative 'fake_os/runner'
