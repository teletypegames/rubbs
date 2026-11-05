# frozen_string_literal: true

require 'securerandom'

module BBS
  # One caller's telnet connection. The server creates one per accepted
  # socket and calls #run in the connection's thread. The line I/O
  # (+readkey+, +readline+, +write+ and the rest) comes from BBS::Telnet.
  class Session
    include Telnet

    # [session_id] a random 16-character hex id for this session
    # [term_cols]  the caller's terminal width in columns (set by
    #              <tt>Telnet#negotiate</tt> and the client's NAWS reports)
    # [term_rows]  the caller's terminal height in rows
    attr_reader :session_id, :term_cols, :term_rows
    # The idle limit in seconds for this session (+nil+: no limit), copied
    # from BBS.config.idle_seconds when the session starts. The Application
    # loop reads it, so a board can give one caller more
    # time (a sysop) or less; see #idle_seconds=.
    attr_reader :idle_seconds

    # Wraps +client+, the accepted socket (any IO with +read+, +write+ and
    # +close+).
    def initialize(client)
      @client       = client
      @session_id   = SecureRandom.hex(8)
      @idle_seconds = BBS.config.idle_seconds
    end

    # Sets this session's idle limit to +seconds+ (+nil+: no limit) and the
    # socket's read/write timeout with it (BBS::Server::DEFAULT_TIMEOUT when
    # +nil+), so a silent line is dropped after the same time at a prompt or
    # inside a door.
    def idle_seconds=(seconds)
      @idle_seconds = seconds
      @client.timeout = seconds || Server::DEFAULT_TIMEOUT if @client.respond_to?(:timeout=)
    end

    # Tells the caller +text+ now, from any thread (the server's shutdown
    # notice): through the handler of #on_announce when the screen has one
    # (a windowed BBS::Application shows a message box), else as a line of
    # its own on the terminal. Returns +nil+; a line that is gone is no
    # error.
    def announce(text)
      handler = @announcer
      handler ? handler.call(text) : write("#{Ansi::CRLF}*** #{text} ***#{Ansi::CRLF}")
      nil
    rescue StandardError
      nil
    end

    # Makes +handler+ (a callable given the text, or +nil+ to stop) show
    # what #announce tells the caller while the screen it belongs to runs.
    def on_announce(handler) = (@announcer = handler)

    # Who the caller is (a BBS::Auth::Identity): the one a neighbouring
    # board handed on with the call (BBS::Auth.from_line), until a login or
    # a logout sets another; a guest otherwise.
    def identity = @identity ||= Auth.from_line(self)

    # Sets who the caller is (a BBS::Auth::Identity).
    attr_writer :identity

    # The face the call got, +:modern+ or +:petscii+ (set by
    # BBS::Terminal.pick, or by the board for its only face); +nil+ while
    # the caller has not got past the terminal question.
    attr_accessor :face

    # The name of the signed-in caller, or +nil+ for a guest. Unlike
    # #identity it does not look at the line: a call whose identity was never
    # asked for is a guest's.
    def caller_name = @identity&.signed_in? ? @identity.name : nil

    # Where the call came from: +"telnet"+ for a line from the internet,
    # the name of the board or proxy that forwarded it (its +BBS_VIA+, such
    # as +"bbs-web"+ or +"ttg-gate-bbs"+), or +"local"+ for a private or
    # loopback line that forwarded nothing (a health check, Uptime Kuma, a
    # door without +forward+). A line without an address is +"local"+ too.
    def call_via
      forwarded_via = forwarded['BBS_VIA'].to_s
      return forwarded_via unless forwarded_via.empty?

      Address.public?(peer_ip) ? 'telnet' : 'local'
    end

    # The key the caller is known by for rate limits: their address, or the
    # line when it is local (BBS::RateLimit.caller_key).
    def caller_key = @caller_key ||= RateLimit.caller_key(self)

    # Lends the line to the block (a gateway to another board, a file
    # transfer): mouse reporting off and the screen cleared on a modern
    # terminal, and afterwards the mouse back as it was. Returns the block's
    # value.
    def hand_over
      mouse = mouse_on?
      disable_mouse
      write("#{Ansi::RESET}#{Ansi::CLEAR}") unless petscii?
      yield self
    ensure
      enable_mouse if mouse
    end

    # Negotiates the telnet options, turns on mouse reporting when
    # BBS.config.mouse and BBS.config.mouse_on_connect are both set, and runs
    # BBS.config.flow for the caller in a BBS::FlowRunner, whose context
    # starts with +:started_at+ (when the call came in). Turns the mouse
    # off and closes the socket when the flow ends or raises. Raises
    # RuntimeError when BBS.config.flow is not set.
    def run
      negotiate
      enable_mouse if BBS.config.mouse && BBS.config.mouse_on_connect
      flow = BBS.config.flow or raise 'BBS.config.flow is not set'
      FlowRunner.new(self, @session_id, flow, context: { started_at: Time.now }).run
    ensure
      disable_mouse rescue nil
      @client.close rescue nil
    end
  end
end
