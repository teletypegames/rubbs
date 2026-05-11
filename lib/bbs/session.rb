# frozen_string_literal: true

require 'securerandom'

module BBS
  class Session
    include Telnet

    attr_reader :session_id, :term_cols, :term_rows

    def initialize(client)
      @client     = client
      @session_id = SecureRandom.hex(8)
    end

    def run
      negotiate
      flow = BBS.config.flow or raise "BBS.config.flow is not set"
      FlowRunner.new(self, @session_id, flow).run
    ensure
      @client.close rescue nil
    end
  end
end
