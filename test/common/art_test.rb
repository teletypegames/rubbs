# frozen_string_literal: true

require 'test_helper'

class ArtTest < Minitest::Test
  ART = <<~YAML
    size: [4, 2]
    charset: petscii-upper
    palette: { y: yellow, c: 51 }
    chars: |
      AB╭╮
      ●  ─
    colors: |
      yy..
      c..y
    reverse: |
      R...
      ....
    hotspots:
      door: [1, 0, 2, 1]
    layers: [snow]
  YAML

  def art = Rubbs::Common::Art.parse(ART)

  def test_reads_cells_colours_and_hotspots
    assert_equal [4, 2], [art.cols, art.rows]
    assert art.cell(0, 0).rvs
    assert_equal Rubbs::Petscii::Canvas::YELLOW, art.cell(0, 0).fg.c64
    assert_nil art.cell(2, 0).fg
    assert_equal Rubbs::Common::Art::Hotspot.new(:door, 1, 0, 2, 1), art.hotspot(:door)
  end

  def test_draws_on_a_canvas_with_rounded_corners
    canvas = Rubbs::Petscii::Art.canvas(art)
    assert_equal 0xd5, canvas.cell(0, 2).code
    assert_equal Rubbs::Petscii::Canvas::LIGHT_GREY, canvas.cell(0, 2).color
  end

  def test_ansi_lines_start_with_their_colours_and_end_with_a_reset
    lines = Rubbs::Modern::Art.lines(art)
    assert_equal 2, lines.size
    assert lines.first.start_with?("\e[0;38;5;")
    assert(lines.all? { |l| l.end_with?(Rubbs::Modern::Ansi::RESET) })
  end

  def test_mistakes_name_the_cell
    bad = ART.sub('c..y', 'c..z')
    error = assert_raises(Rubbs::Common::Art::Error) { Rubbs::Common::Art.parse(bad) }
    assert_match(/colors row 1 col 3/, error.message)
    assert_raises(Rubbs::Common::Art::Error) { Rubbs::Common::Art.parse(ART.sub('[1, 0, 2, 1]', '[3, 0, 2, 1]')) }
    assert_raises(Rubbs::Common::Art::Error) { Rubbs::Common::Art.parse(ART.sub('size: [4, 2]', 'size: [4]')) }
  end

  def test_layers_cover_the_cells_they_draw
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'house.yml'), ART)
      File.write(File.join(dir, 'snow.yml'), "at: [1, 1]\nchars: |\n  *\ncolors: |\n  y\nsize: [1, 1]\n")
      snowy = Rubbs::Common::Art.load(File.join(dir, 'house.yml'), layers: :all)
      assert_equal '*', snowy.cell(1, 1).char
      assert_equal 'A', snowy.cell(0, 0).char
      assert_equal ['snow'], snowy.stacked
    end
  end
end
