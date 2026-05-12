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
        client = begin
          server.accept
        rescue Errno::ECONNABORTED, Errno::EMFILE, Errno::ENFILE, IOError => e
          warn "BBS accept error: #{e.class}: #{e.message}"
          next
        end

        Thread.new(client) do |c|
          session = Session.new(c)
          begin
            session.run
          rescue StandardError => e
            warn "BBS session error: #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
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
