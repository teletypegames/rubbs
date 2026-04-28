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
        Thread.new(client) do |c|
          session = Session.new(c)
          begin
            session.run
          rescue => e
            nil
          ensure
            BBS.config.on_session_end&.call(session)
          end
        end
      end
    rescue Interrupt
      puts "\nServer stopped."
    end
  end
end
