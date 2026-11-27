# frozen_string_literal: true

require 'minitest'

module Rubbs
  module Test
    # A Minitest test case for a board that plays a caller: each test calls
    # a board, a flow or a screen on a ScriptedLine and presses keys, then
    # looks at what the caller sees.
    #
    #   class GuestbookTest < Rubbs::Test::Case
    #     test 'a C64 caller signs the guestbook' do
    #       call(->(line) { UI::Petscii.new(line, {}, board).run }, face: :petscii) do
    #         press 's'
    #         type 'hello', enter: true
    #         see 'THANK YOU FOR SIGNING'
    #         never_see 'ERROR'
    #       end
    #     end
    #   end
    #
    # Each test runs with a copy of Rubbs.config, put back after it, and the
    # tokens taken so far forgotten (Rubbs::Common::Auth::Token.forget!).
    class Case < Minitest::Test
      # Defines a test named +description+ that runs the block. Raises
      # ArgumentError when the class has a test of that name already.
      #
      #   test('the menu has a log off') { … }
      def self.test(description, &)
        name = "test_#{description.to_s.strip.downcase.gsub(/\W+/, '_')}"
        raise ArgumentError, "#{self.name} has a test #{description.inspect} already" if method_defined?(name)

        define_method(name, &)
      end

      # Keeps Rubbs.config (a copy is used in the test) and forgets the tokens.
      def setup
        super
        @config_before = Rubbs.config
        Rubbs.config = @config_before.dup
        Common::Auth::Token.forget!
      end

      # Puts back the Rubbs.config kept by #setup.
      def teardown
        Rubbs.config = @config_before
        super
      end

      # Calls +target+ on a fresh ScriptedLine and runs the block against it
      # (#press, #type, #see, #never_see, #hang_up), the call in its own thread.
      # After the block the caller hangs up; an error the call raised is
      # raised here (a Rubbs::Common::Line::Hangup is a hang-up, not an error).
      #
      # [target] a Rubbs::Common::Call::Flow (run as the server runs a call:
      #          Rubbs.config.flow is one), or anything that answers
      #          <tt>call(line)</tt> (a screen to run)
      # [face]   +:modern+ or +:petscii+: the line's face, forwarded as BBS_FACE
      #          so a board's terminal question is passed
      # [as]     who calls: a name or a Rubbs::Common::Auth::Identity (a guest
      #          when +nil+)
      # [line]   further options of the ScriptedLine (+cols+, +rows+, +forwarded+ …)
      #
      # Returns the line.
      def call(target, face: :modern, as: nil, **line, &script)
        forwarded = { 'BBS_FACE' => face.to_s, **line.delete(:forwarded).to_h }
        identity  = as && Test.identity_of(as)
        @line = ScriptedLine.new(petscii: face == :petscii, forwarded: forwarded, identity: identity, **line)
        @runner = Thread.new { run_target(target, @line) }
        @line.until_asked(-1, @runner)
        instance_exec(&script) if script
        finish
        @line
      end

      # The line of the last #call.
      attr_reader :line

      # Presses +keys+ one by one (Strings, or Symbols such as +:enter+,
      # +:down+, +:escape+), each after the board asked for it.
      def press(*keys) = keys.each { |key| @line.press(key, runner: @runner) }

      # Types +text+ a character at a time; RETURN after it with +enter+.
      def type(text, enter: false) = press(*text.chars, *([:enter] if enter))

      # Asserts that the caller sees +text+ (Rubbs::Test.screen_text: the
      # screen now on a C64, everything written on a modern line).
      def see(text) = assert_includes(screen, text)

      # Asserts that the caller does not see +text+ (as #see looks).
      def never_see(text) = refute_includes(screen, text)

      # What the caller sees now (Rubbs::Test.screen_text of the line).
      def screen = Test.screen_text(@line)

      # Drops the line in the middle of the script.
      def hang_up = @line.hang_up

      private

      def run_target(target, line)
        Thread.current.report_on_exception = false
        if target.is_a?(Common::Call::Flow)
          Common::Call::FlowRunner.new(line, line.session_id, target, context: { started_at: Time.now }).run
        else
          target.call(line)
        end
      rescue Common::Line::Hangup
        nil
      end

      def finish
        @line.hang_up
        @runner.join(ScriptedLine::WAIT) or raise ScriptedLine::Stuck, 'the call did not end after the hang-up'
        @runner.value
      end
    end
  end
end
