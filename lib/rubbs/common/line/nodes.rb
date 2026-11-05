# frozen_string_literal: true

module Rubbs
  module Common
    module Line
      # The node numbers of a board: each call gets the lowest number no other
      # call has, for the length of the call, the way a multi-line BBS showed
      # "Node 2". Thread-safe; one instance is shared by the calls it counts.
      #
      #   NODES = Rubbs::Common::Line::Nodes.new
      #   NODES.take { |node| screen.header("Node #{node}") ... }
      class Nodes
        # Creates a counter with no node taken.
        def initialize
          @taken = []
          @lock  = Mutex.new
        end

        # Yields the lowest free node number (1 and up) and frees it when the
        # block ends, however it ends. Returns the block's value.
        def take
          node = @lock.synchronize { (1..).find { |n| !@taken.include?(n) }.tap { |n| @taken << n } }
          yield node
        ensure
          @lock.synchronize { @taken.delete(node) } if node
        end

        # The node numbers taken now, lowest first.
        def taken = @lock.synchronize { @taken.sort }
      end
    end
  end
end
