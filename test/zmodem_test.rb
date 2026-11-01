# frozen_string_literal: true

require 'test_helper'

class ZmodemTest < Minitest::Test
  Z = BBS::Zmodem

  # A receiver that answers every wait with ZRPOS 0, for ever.
  class StubbornReceiver
    attr_reader :sent

    def initialize
      frame  = [Z::ZRPOS, 0, 0, 0, 0].pack('C*')
      @bytes = "#{Z::HEX_HEADER}#{(frame + [Z.crc16(frame)].pack('n')).unpack1('H*')}\r\n".bytes
      @at    = 0
      @sent  = 0
    end

    def read_raw_byte(timeout)
      return :timeout if timeout.zero?

      @bytes[(@at += 1) % @bytes.size]
    end

    def write_raw(bytes)
      @sent += bytes.bytesize
    end
  end

  def sender(receiver)
    Z::Sender.new(receiver).tap do |s|
      s.instance_variable_set(:@window, 0)
      s.instance_variable_set(:@crc32, false)
    end
  end

  def test_pending_bytes_are_capped
    s = Z::Sender.new(nil)
    10_000.times { s.send(:push, 0x41) }
    assert_equal Z::MAX_PENDING, s.instance_variable_get(:@pending).size
  end

  def test_restarts_are_limited
    receiver = StubbornReceiver.new
    assert_raises(Z::Cancelled) { sender(receiver).send(:stream, ''.b, 0) }
  end

  def test_bytes_sent_are_limited
    receiver = StubbornReceiver.new
    data     = 'x' * 10_000
    assert_raises(Z::Cancelled) { sender(receiver).send(:stream, data, 0) }
    assert_operator receiver.sent, :<, (Z::BUDGET_FACTOR + 1) * data.bytesize * 2
  end
end
