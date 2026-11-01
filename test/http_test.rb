# frozen_string_literal: true

require 'test_helper'

class HTTPTest < Minitest::Test
  def setup
    @server = TinyHTTP.new do |path, client|
      case path
      when %r{\A/ok} then client.write(http_response(200, 'hello', 'X-Test' => 'yes'))
      when '/big'    then client.write(http_response(200, 'x' * 100_000))
      when '/slow'   then sleep 3
      when '/trickle'
        client.write("HTTP/1.1 200 X\r\nContent-Length: 100\r\n\r\n")
        20.times { client.write('x') && sleep(0.1) }
      when '/hop'    then client.write(http_response(302, '', 'Location' => '/ok'))
      when '/loop'   then client.write(http_response(302, '', 'Location' => '/loop'))
      when '/ftp'    then client.write(http_response(301, '', 'Location' => 'ftp://example.org/x'))
      when '/post'   then client.write(http_response(201, 'made'))
      end
    end
  end

  def teardown = @server.close

  def get(path, **) = BBS::HTTP.get(@server.url(path), public_only: false, **)

  def test_get
    response = get('/ok')
    assert_equal 200, response.status
    assert_equal 'hello', response.body
    assert_equal 'yes', response.headers['x-test']
    assert response.ok?
  end

  def test_post
    response = BBS::HTTP.post(@server.url('/post'), body: 'q=1', public_only: false)
    assert_equal [201, 'made'], [response.status, response.body]
  end

  def test_redirect_followed
    assert_equal 'hello', get('/hop').body
  end

  def test_too_many_redirects
    error = assert_raises(BBS::HTTP::Error) { get('/loop', redirects: 2) }
    assert_match(/too many redirects/, error.message)
  end

  def test_redirect_to_another_scheme_refused
    error = assert_raises(BBS::HTTP::Error) { get('/ftp') }
    assert_match(/not an http or https address/, error.message)
  end

  def test_body_cap
    error = assert_raises(BBS::HTTP::Error) { get('/big', max_bytes: 1000) }
    assert_match(/over 1000 bytes/, error.message)
  end

  def test_read_timeout_within_deadline
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(BBS::HTTP::Error) { get('/slow', deadline: 0.5) }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  def test_deadline_stops_a_trickle
    error = assert_raises(BBS::HTTP::Error) { get('/trickle', deadline: 0.5, read_timeout: 5) }
    assert_match(/deadline|Timeout/, error.message)
  end

  def test_public_only_refuses_loopback
    error = assert_raises(BBS::HTTP::Error) { BBS::HTTP.get(@server.url('/ok')) }
    assert_match(/not a public address/, error.message)
  end

  def test_error_message_has_no_query
    error = assert_raises(BBS::HTTP::Error) { BBS::HTTP.get("#{@server.url('/ok')}?key=SECRET") }
    refute_match(/SECRET|key=/, error.message)
    assert_match(%r{GET http://127\.0\.0\.1/ok}, error.message)
  end

  def test_connection_refused_is_an_error
    port = @server.port
    @server.close
    assert_raises(BBS::HTTP::Error) { BBS::HTTP.get("http://127.0.0.1:#{port}/", public_only: false, deadline: 2) }
  end

  def test_bad_url
    assert_raises(BBS::HTTP::Error) { BBS::HTTP.get('not a url') }
    assert_raises(BBS::HTTP::Error) { BBS::HTTP.get('file:///etc/passwd') }
  end
end
