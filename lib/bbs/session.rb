# frozen_string_literal: true

require 'securerandom'

module BBS
  class Session
    include Telnet

    attr_reader :session_id, :term_cols, :term_rows
    attr_accessor :idle_seconds

    def initialize(client)
      @client       = client
      @session_id   = SecureRandom.hex(8)
      @idle_seconds = BBS.config.idle_seconds
    end

    def run
      negotiate
      enable_mouse if BBS.config.mouse && BBS.config.mouse_on_connect
      flow = BBS.config.flow or raise "BBS.config.flow is not set"
      FlowRunner.new(self, @session_id, flow).run
    ensure
      disable_mouse rescue nil
      @client.close rescue nil
    end
  end
end
