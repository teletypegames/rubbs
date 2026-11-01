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
    # loop and the TUI runner read it, so a board can give one caller more
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

    # Negotiates the telnet options, turns on mouse reporting when
    # BBS.config.mouse and BBS.config.mouse_on_connect are both set, and runs
    # BBS.config.flow for the caller in a BBS::FlowRunner. Turns the mouse
    # off and closes the socket when the flow ends or raises. Raises
    # RuntimeError when BBS.config.flow is not set.
    def run
      negotiate
      enable_mouse if BBS.config.mouse && BBS.config.mouse_on_connect
      flow = BBS.config.flow or raise 'BBS.config.flow is not set'
      FlowRunner.new(self, @session_id, flow).run
    ensure
      disable_mouse rescue nil
      @client.close rescue nil
    end
  end
end
