# frozen_string_literal: true

require 'ipaddr'

module BBS
  # What an IP address is: a caller's own line on the internet, or one of
  # the board's neighbours (a proxy on the Docker network, the loopback).
  #
  #   BBS::Address.local?('172.18.0.5')    # => true  (bbs-web on the stack)
  #   BBS::Address.public?('100.64.1.2')   # => false (carrier-grade NAT)
  module Address
    # The ranges that are not on the public internet beyond what IPAddr
    # tells (private, loopback, link-local): this network, carrier-grade
    # NAT, the IETF, documentation and benchmark ranges, multicast and the
    # reserved block, IPv6 unspecified, IPv4-translated, discard,
    # documentation and multicast.
    NON_PUBLIC = %w[
      0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15
      198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 64:ff9b::/96 100::/64 2001:db8::/32 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    # Returns +ip+ (a String or an IPAddr) as an IPAddr, an IPv4-mapped
    # IPv6 address as its IPv4 one; +nil+ when it is not an IP address.
    def parse(ip)
      (ip.is_a?(IPAddr) ? ip : IPAddr.new(ip.to_s)).native
    rescue IPAddr::Error
      nil
    end

    # Returns whether +ip+ is a neighbour of the board: a private, loopback
    # or link-local address (IPv6 unique local included). +false+ for
    # anything that is not an IP address.
    def local?(ip)
      addr = parse(ip) or return false
      addr.private? || addr.loopback? || addr.link_local?
    end

    # Returns whether +ip+ is an address on the public internet: not
    # #local? and in none of the NON_PUBLIC ranges. +false+ for anything
    # that is not an IP address.
    def public?(ip)
      addr = parse(ip) or return false
      !local?(addr) && NON_PUBLIC.none? { |range| range.family == addr.family && range.include?(addr) }
    end
  end
end
