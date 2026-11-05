# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      module Telnet
        # Who is really calling when the call comes through another board: the
        # variables a forwarding Rubbs::Common::Line::Gateway sends (Environ::FORWARDED), as the
        # +X-Forwarded-For+ of a proxy is in HTTP. They are believed only from a
        # neighbour, a line from a private or loopback address
        # (Rubbs::Common::Line::Address.local?: the boards of one host call each other so);
        # from anywhere else a caller could claim any address, so #forwarded is
        # empty and everything falls back to the line itself.
        module Forwarded
          # The IP address of the line itself as a String (the gateway's, for a
          # forwarded call), or +nil+ when it has none. Asked once and kept, so
          # it is still known after the line closed (the +call ended+ line).
          def peer_ip
            return @peer_ip if defined?(@peer_ip)

            @peer_ip = begin
              line.remote_address.ip_address
            rescue StandardError
              nil
            end
          end

          # The variables the line sent with NEW-ENVIRON, believed or not: a
          # Hash of name => value, empty until some came.
          def telnet_env = @telnet_env ||= {}

          # The forwarded variables (Environ::FORWARDED) when the line is a
          # neighbour's (see the module), else an empty Hash.
          def forwarded
            return {} unless Address.local?(peer_ip)

            telnet_env.slice(*Environ::FORWARDED)
          end

          # The face the caller picked on the board the call came through,
          # +:modern+ or +:petscii+; +nil+ when it was not forwarded.
          def forwarded_face
            face = forwarded['BBS_FACE']
            %w[modern petscii].include?(face) ? face.to_sym : nil
          end

          # The name of the board the call came through, or +nil+.
          # (Rubbs::Common::Line::Session#call_via also names a call that was not forwarded.)
          def via = forwarded['BBS_VIA']

          # The caller's IP address as a String: the forwarded one when it is a
          # valid address, else the line's own (#peer_ip), +nil+ without one.
          def caller_ip
            ip = Address.parse(forwarded['BBS_CLIENT_IP'])
            ip ? ip.to_s : peer_ip
          end

          private

          # Keeps the variables of a NEW-ENVIRON subnegotiation, at most
          # Environ::MAX_VARIABLES of them.
          def take_environ(bytes)
            Environ.parse(bytes).each do |name, value|
              break if telnet_env.size >= Environ::MAX_VARIABLES && !telnet_env.key?(name)

              telnet_env[name] = value
            end
          end
        end
      end
    end
  end
end
