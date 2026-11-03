# frozen_string_literal: true

require 'test_helper'

class MediaWikiTest < Minitest::Test
  ENDPOINT = 'https://memory-alpha.fandom.com/api.php'

  def answer(status, body) = BBS::HTTP::Response.new(status: status, body: body.b, headers: {})

  def wiki(**) = BBS::MediaWiki.new(endpoint: ENDPOINT, user_agent: 'Board (+x)', name: 'Memory Alpha', **)

  def test_get_asks_the_endpoint_and_parses_the_json
    url = nil
    get = lambda do |address, **options|
      url = address
      assert_equal 'Board (+x)', options[:user_agent]
      answer(200, '{"query":{"search":[{"title":"Tribble"}]}}')
    end
    data = BBS::HTTP.stub(:get, get) { wiki.get(action: 'query', srsearch: 'tribbles') }
    assert_equal 'Tribble', data.dig('query', 'search', 0, 'title')
    assert_equal "#{ENDPOINT}?action=query&srsearch=tribbles&format=json&formatversion=2", url
  end

  def test_errors_name_the_wiki
    error = BBS::HTTP.stub(:get, answer(503, 'down')) { assert_raises(BBS::MediaWiki::Error) { wiki.get } }
    assert_equal 'Memory Alpha answered 503', error.message
    assert_kind_of BBS::HTTP::Error, error
  end

  def test_requests_are_paced
    paced = wiki(rate: 1, max_wait: 0)
    BBS::HTTP.stub(:get, answer(200, '{}')) do
      paced.get
      assert_raises(BBS::MediaWiki::Error) { paced.get }
    end
  end

  def test_wikipedia_is_one_with_its_own_error
    assert_operator BBS::Wikipedia, :<, BBS::MediaWiki
    assert_operator BBS::Wikipedia::Error, :<, BBS::MediaWiki::Error
  end
end

class MediaWikiExtractTest < Minitest::Test
  Extract = BBS::MediaWiki::Extract

  def test_sections_skip_the_references_and_keep_deeper_headings
    extract = "Lead.\n== History ==\n=== Early ===\nBorn.\n== See also ==\nx"
    assert_equal [['Ada', 'Lead.'], ['History', "## Early\n\nBorn."]], Extract.sections('Ada', extract)
  end

  def test_a_board_names_its_own_sections_to_skip
    extract = "Lead.\n== Summary ==\nS.\n== Appendices ==\nA."
    assert_equal [%w[T Lead.], %w[Summary S.]], Extract.sections('T', extract, skip: ['appendices'])
  end

  def test_a_formula_becomes_its_tex_made_readable
    assert_equal [['F', 'x = α +1 ok']], Extract.sections('F', 'x = {\\displaystyle \\alpha +1} ok')
  end

  def test_a_line_that_looks_like_markdown_is_escaped
    assert_equal [['T', "\\#tag\n\n\\> quote"]], Extract.sections('T', "#tag\n> quote")
  end
end

class WikidataTest < Minitest::Test
  def answer(status, body) = BBS::HTTP::Response.new(status: status, body: body.b, headers: {})

  def test_select_posts_the_query_and_returns_the_rows
    sent = nil
    post = lambda do |_url, body:, **|
      sent = URI.decode_www_form(body).to_h['query']
      answer(200, '{"results":{"bindings":[{"item":{"value":"http://www.wikidata.org/entity/Q1077"}}]}}')
    end
    rows = BBS::HTTP.stub(:post, post) { BBS::Wikidata.new(user_agent: 'x', pause: 0).select('SELECT ?item {}') }
    assert_equal 'SELECT ?item {}', sent
    assert_equal(['Q1077'], rows.map { |r| BBS::Wikidata.qid(r['item']) })
  end

  def test_an_error_status_or_no_json_is_an_error
    wikidata = BBS::Wikidata.new(user_agent: 'x', pause: 0)
    BBS::HTTP.stub(:post, answer(429, 'slow down')) { assert_raises(BBS::Wikidata::Error) { wikidata.select('x') } }
    BBS::HTTP.stub(:post, answer(200, '<html>')) { assert_raises(BBS::Wikidata::Error) { wikidata.select('x') } }
  end

  def test_text_and_qid_of_a_binding
    assert_equal 'Kirk', BBS::Wikidata.text({ 'value' => " Kirk\n" })
    assert_equal '', BBS::Wikidata.text(nil)
    assert_nil BBS::Wikidata.qid({ 'value' => 'literal' })
  end
end
