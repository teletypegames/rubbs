# frozen_string_literal: true

require 'test_helper'

class WikipediaTest < Minitest::Test
  def answer(status, body) = BBS::HTTP::Response.new(status: status, body: body.b, headers: {})

  def test_get_asks_the_action_api_and_parses_the_json
    url = nil
    get = lambda do |address, **options|
      url = address
      assert_equal 'Board (+x)', options[:user_agent]
      answer(200, '{"query":{"random":[{"title":"Ada"}]}}')
    end
    data = BBS::HTTP.stub(:get, get) { BBS::Wikipedia.new(user_agent: 'Board (+x)').get('hu', action: 'query') }
    assert_equal 'Ada', data.dig('query', 'random', 0, 'title')
    assert_equal 'https://hu.wikipedia.org/w/api.php?action=query&format=json&formatversion=2', url
  end

  def test_an_error_status_or_no_json_is_an_error
    wiki = BBS::Wikipedia.new(user_agent: 'x')
    BBS::HTTP.stub(:get, answer(503, 'down')) { assert_raises(BBS::Wikipedia::Error) { wiki.get('en') } }
    error = BBS::HTTP.stub(:get, answer(200, '<html>')) { assert_raises(BBS::HTTP::Error) { wiki.get('en') } }
    assert_match(/no JSON/, error.message)
  end

  def test_requests_are_paced
    wiki = BBS::Wikipedia.new(user_agent: 'x', rate: 2, max_wait: 0)
    BBS::HTTP.stub(:get, answer(200, '{}')) do
      2.times { wiki.get('en') }
      assert_raises(BBS::Wikipedia::Error) { wiki.get('en') }
    end
  end
end
