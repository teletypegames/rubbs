# frozen_string_literal: true

require 'socket'

module BBS
  class Server
    def initialize(port:)
      @port = port
    end

    def run
      server = TCPServer.new('0.0.0.0', @port)
      puts "BBS listening on port #{@port} — connect with: telnet localhost #{@port}"
      loop do
        client = server.accept
        Thread.new(client) { |c| Session.new(c).run rescue nil }
      end
    rescue Interrupt
      puts "\nServer stopped."
    end
  end
end
