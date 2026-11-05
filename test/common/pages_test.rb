# frozen_string_literal: true

require_relative '../test_helper'
require 'rubbs/test'

class PagesTest < Minitest::Test
  # A list of words: up and down light one, RETURN opens it, Q goes back.
  class Words < Rubbs::Common::Screens::Page
    attr_reader :index, :resumed

    key(:up)   { @index = [@index - 1, 0].max }
    key(:down) { @index = [@index + 1, @words.size - 1].min }
    key(:enter) { push(Word.new(@words[@index])) }
    key('x') { pass }
    key('q', :escape) { back }

    def initialize(words)
      super()
      @words = words
      @index = 0
      @resumed = 0
    end

    def resume = @resumed += 1

    def draw(screen)
      if screen.is_a?(Rubbs::Modern::FrameBuffer)
        lines = @words.each_with_index.map { |w, i| i == @index ? "\e[7m#{w}\e[0m" : w }
        print_lines(screen, lines, x: 3)
      else
        @words.each_with_index { |w, i| screen.text(i, 1, w, i == @index ? :cyan : :white, rvs: i == @index) }
      end
    end
  end

  # One word, alone.
  class Word < Rubbs::Common::Screens::Page
    key('q') { back }

    def initialize(word)
      super()
      @word = word
    end

    def draw(screen)
      screen.is_a?(Rubbs::Modern::FrameBuffer) ? print_lines(screen, ["Word: #{@word}"]) : screen.text(0, 0, @word, :white)
    end
  end

  # A runner with a key of its own and a frame around the page.
  class App < Rubbs::Common::Screens::Pages
    attr_reader :ticks

    key('x') { @x = true }
    key('h') { quit :hung_up }
    every(0.5) { @ticks = (@ticks || 0) + 1 }

    def x? = @x

    def draw(screen)
      super
      screen.is_a?(Rubbs::Modern::FrameBuffer) ? print_status(screen) : screen.text(24, 0, 'Status', :grey)
    end

    def print_status(frame)
      frame.move(1, frame.rows)
      frame.write('Status')
      cursor(frame.rows, 8) if line
    end
  end

  def session(keys = [], **) = Rubbs::Test::Session.new(keys: keys, **)

  def test_the_keys_move_and_the_repaint_is_what_changed
    s = session
    pages = Rubbs::Common::Screens::Pages.new(s)
    first = pages.start(Words.new(%w[alpha beta gamma]))
    assert_includes first, "\e[2J"
    assert_includes first, 'alpha'
    pages.press(:down)
    step = s.last
    refute_includes step, "\e[2J"
    assert_includes step, 'beta'
    refute_includes step, 'gamma'
    assert_equal 1, pages.page.index
    assert_equal '', pages.redraw
  end

  def test_push_back_resume_and_quit
    s = session([:down, :enter, 'q', 'q'])
    pages = Rubbs::Common::Screens::Pages.new(s)
    words = Words.new(%w[alpha beta])
    assert_nil pages.run(words)
    assert pages.done?
    assert_equal 1, words.resumed
    assert_includes s.output, 'Word: beta'
  end

  def test_a_hang_up_raises
    assert_raises(Rubbs::Common::Line::Hangup) { Rubbs::Common::Screens::Pages.new(session([:down])).run(Words.new(%w[a b])) }
  end

  def test_the_runner_keys_come_after_the_page_and_pass_reaches_them
    pages = App.new(session)
    pages.start(Words.new(%w[a b]))
    refute pages.press('x')
    assert pages.x?
    assert pages.press('h')
    assert_equal :hung_up, pages.result
  end

  def test_a_timer_ticks_while_the_caller_is_silent_and_idle_ends
    s = session([:idle, :idle, 'h'])
    app = App.new(s)
    assert_equal :hung_up, app.run(Words.new(%w[a]))
    assert_equal 2, app.ticks
    s = session([:idle] * 3)
    s.idle_seconds = 0
    assert_nil App.new(s).run(Words.new(%w[a]))
  end

  def test_show_waits_for_an_answer_and_takes_the_page_off
    s = session(%w[z n])
    pages = Rubbs::Common::Screens::Pages.new(s)
    pages.start(Words.new(%w[a]))
    answer = pages.show(Word.new('sure?')) { |k| { 'y' => true, 'n' => false }[k] }
    assert_equal false, answer
    assert_instance_of Words, pages.page
    assert_equal 1, pages.stack.size
    s.keys << 'k'
    assert_equal 'k', pages.show(Word.new('any'))
  end

  def test_read_line_draws_through_the_screen_and_shows_the_cursor
    s = session(['h', 'i', :backspace, 'o', :enter])
    app = App.new(s)
    app.start(Words.new(%w[a]))
    assert_equal 'ho', app.read_line('Find:', max: 5)
    assert_nil app.line
    assert_includes s.output, "\e[24;8H\e[?25h"
    s.keys.push('a', :escape)
    assert_nil app.read_line
  end

  def test_hand_over_clears_restores_and_repaints_whole
    s = session
    pages = Rubbs::Common::Screens::Pages.new(s)
    pages.start(Words.new(%w[a]))
    assert_equal(42, pages.hand_over { s.write('BOARD'); 42 })
    assert_equal "#{Rubbs::Common::Screens::Pages::MODERN_CLEAR}#{Rubbs::Modern::Ansi::SHOW_CURSOR}", s.writes[-3]
    assert_equal Rubbs::Common::Screens::Pages::MODERN_RESTORE, s.writes[-1]
    assert_includes pages.redraw, "\e[2J"
  end

  def test_the_c64_face_draws_a_canvas_in_its_set
    s = session(petscii: true)
    pages = App.new(s, charset: :lower)
    assert pages.petscii?
    first = pages.start(Words.new(%w[alpha beta]))
    assert_equal Rubbs::Petscii::Canvas::LOWERCASE, first.getbyte(0)
    shown = Rubbs::Petscii::Canvas.new.feed(first)
    assert_equal 'alpha', shown.to_s.lines[0].strip
    s.take
    pages.press(:down)
    step = s.take.b
    refute_includes step.bytes, Rubbs::Petscii::Canvas::CLEAR
    shown.feed(step)
    assert shown.cell(1, 1).rvs
    pages.hand_over { nil }
    assert_equal [Rubbs::Petscii::Canvas::LOWERCASE, Rubbs::Petscii::Canvas::CLEAR], s.last.bytes
  end

  def test_the_key_map_is_inherited_and_needs_a_block
    sub = Class.new(Words) { key('q') { @sub = true } }
    assert_equal 6, sub.keymap.size
    assert_raises(ArgumentError) { sub.key('z') }
    assert_raises(ArgumentError) { sub.every(0) { nil } }
    assert_raises(ArgumentError) { Rubbs::Common::Screens::Pages.new(session, face: :teletext) }
  end
end
