# frozen_string_literal: true

require 'test_helper'

class ForwardedTest < Minitest::Test
  E = BBS::Telnet::Environ

  def setup = @session = FakeSession.new

  def teardown = @session.fake_line.close

  def from(ip) = @session.define_singleton_method(:peer_ip) { ip }

  # Sends +vars+ as the forwarding gateway does and lets the board read them.
  def forward(vars, naws: true)
    bytes = E.info(vars)
    bytes += [255, 250, 31, 0, 100, 0, 30, 255, 240].pack('C*') if naws
    @session.fake_line.caller.write(bytes)
    @session.settle(timeout: 0.3)
  end

  def test_info_and_parse_round_trip_with_escapes
    sub = E.info('A' => "x\u0001y", 'BBS_FACE' => 'petscii').b
    parsed = {}
    BBS::Telnet::Parser.new { |_, arg| parsed.merge!(E.parse(arg)) }.parse(sub)
    assert_equal({ 'A' => "x\u0001y", 'BBS_FACE' => 'petscii' }, parsed)
  end

  def test_only_is_and_info_carry_variables
    assert_empty E.parse([39, E::SEND, E::USERVAR, *'X'.bytes])
    assert_equal({ 'X' => '' }, E.parse([39, E::IS, E::VAR, *'X'.bytes]))
  end

  def test_a_neighbour_is_believed
    from('172.18.0.2')
    forward({ 'BBS_FACE' => 'petscii', 'BBS_CLIENT_IP' => '203.0.113.7', 'BBS_VIA' => 'ttg-gate-bbs' })
    assert_equal :petscii, @session.forwarded_face
    assert_equal '203.0.113.7', @session.caller_ip
    assert_equal 'ttg-gate-bbs', @session.via
    assert_equal '203.0.113.7', BBS::RateLimit.caller_key(@session)
  end

  def test_a_caller_from_the_internet_is_not
    from('198.51.100.9')
    forward({ 'BBS_FACE' => 'petscii', 'BBS_CLIENT_IP' => '203.0.113.7' })
    assert_nil @session.forwarded_face
    assert_equal '198.51.100.9', @session.caller_ip
    assert_equal({ 'BBS_FACE' => 'petscii', 'BBS_CLIENT_IP' => '203.0.113.7' }, @session.telnet_env)
  end

  def test_a_bad_address_or_face_falls_back
    from('10.0.0.5')
    forward({ 'BBS_FACE' => 'vt52', 'BBS_CLIENT_IP' => 'nope' })
    assert_nil @session.forwarded_face
    assert_equal '10.0.0.5', @session.caller_ip
  end

  def test_a_forwarded_call_skips_the_question_and_the_splash
    from('172.18.0.2')
    @session.fake_line.caller.write(E.info('BBS_FACE' => 'modern'))
    @session.fake_line.caller.write([255, 250, 31, 0, 100, 0, 30, 255, 240].pack('C*'))
    splash = Object.new
    def splash.continue?(*) = raise('no splash for a forwarded call')
    reached = nil
    modern  = BBS::Flow.define { call { |_ctx, _r| reached = :modern; nil } }
    flow    = BBS::Terminal.flow(title: 'X', modern: modern, petscii: modern, splash: splash)
    Timeout.timeout(5) { BBS::FlowRunner.new(@session, 'id', flow).run }
    assert_equal :modern, reached
    refute_includes @session.received, 'YOUR TERMINAL'
  end

  def test_a_forwarding_gateway_sends_who_is_calling_first
    from('203.0.113.7')
    server = TCPServer.new('127.0.0.1', 0)
    got = Queue.new
    Thread.new do
      c = server.accept
      got << c.readpartial(512)
      c.close
    end
    Thread.new { sleep 0.5; @session.fake_line.caller.write('x') }
    BBS::Gateway.new(host: '127.0.0.1', port: server.addr[1], public_only: false, forward: true).call(@session)
    vars = {}
    BBS::Telnet::Parser.new { |_, arg| vars.merge!(E.parse(arg)) }.parse(Timeout.timeout(5) { got.pop })
    assert_equal 'modern', vars['BBS_FACE']
    assert_equal '203.0.113.7', vars['BBS_CLIENT_IP']
  ensure
    server&.close
  end

  def test_a_plain_gateway_sends_nothing_of_the_caller
    server = TCPServer.new('127.0.0.1', 0)
    got = Queue.new
    Thread.new do
      c = server.accept
      got << (c.wait_readable(0.3) ? c.readpartial(512) : '')
      c.close
    end
    Thread.new { sleep 0.6; @session.fake_line.caller.write('x') }
    BBS::Gateway.new(host: '127.0.0.1', port: server.addr[1], public_only: false).call(@session)
    refute_includes Timeout.timeout(5) { got.pop }.b, [255, 250, 39].pack('C*')
  ensure
    server&.close
  end
end
