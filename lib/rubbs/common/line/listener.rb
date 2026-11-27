# frozen_string_literal: true

require 'socket'

module Rubbs
  module Common
    module Line
      # A listening TCP socket that a board's next process may open on the
      # same port while this one still listens: +SO_REUSEPORT+ (where the
      # system has it), so a deploy hands the port over without a moment
      # closed (Server#drain). The telnet line, the Central's HTTP and a
      # board's own HTTP API open theirs here.
      #
      #   server = Rubbs::Common::Line::Listener.tcp('0.0.0.0', 2323)
      #   server.accept
      module Listener
        # The connections waiting to be accepted at most.
        BACKLOG = 128

        # A TCPServer listening on +port+ (0: one the system chooses) of
        # +host+, opened with +SO_REUSEADDR+ and +SO_REUSEPORT+.
        def self.tcp(host, port)
          socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true) if reuse_port?
          socket.bind(Addrinfo.tcp(host, port))
          socket.listen(BACKLOG)
          socket.autoclose = false
          TCPServer.for_fd(socket.fileno)
        rescue StandardError
          socket&.close rescue nil
          raise
        end

        # Whether the system lets two sockets listen on one port.
        def self.reuse_port? = defined?(Socket::SO_REUSEPORT) ? true : false
      end
    end
  end
end
