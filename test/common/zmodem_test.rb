# frozen_string_literal: true

require 'test_helper'

class ZmodemTest < Minitest::Test
  Z = Rubbs::Common::Files::Zmodem

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

  # A line that keeps what is written to it.
  class Tape
    attr_reader :bytes

    def initialize = @bytes = +''.b
    def write_raw(bytes) = @bytes << bytes
  end

  def stream(receiver) = Z::Stream.new(Z::Input.new(receiver), Z::Output.new(receiver, telnet: true), 0)

  def test_pending_bytes_are_capped
    input = Z::Input.new(nil)
    10_000.times { input.send(:push, 0x41) }
    assert_equal Z::MAX_PENDING, input.instance_variable_get(:@pending).size
  end

  def test_headers_written_are_read_back
    [false, true].each do |crc32|
      tape = Tape.new
      out  = Z::Output.new(tape, telnet: false).tap { |o| o.crc32 = crc32 }
      out.hex_header(Z::ZRPOS, [1, 2, 0, 0])
      out.bin_header(Z::ZDATA, [0x18, 0x11, 0x91, 0])
      buf = tape.bytes.bytes
      first, used = Z::Frames.parse(buf)
      buf = buf.drop(used).drop_while { |b| b != Z::ZPAD }
      second, = Z::Frames.parse(buf)
      assert_equal [Z::ZRPOS, 513], [first.type, first.position]
      assert_equal [Z::ZDATA, [0x18, 0x11, 0x91, 0]], [second.type, second.bytes]
    end
  end

  def test_a_broken_crc_is_no_header
    tape = Tape.new
    Z::Output.new(tape, telnet: false).bin_header(Z::ZACK, [1, 2, 3, 4])
    buf = tape.bytes.bytes
    buf[-1] ^= 1
    header, used = Z::Frames.parse(buf)
    assert_nil header
    assert_equal buf.size, used
  end

  def test_iac_is_doubled_on_a_telnet_line
    tape = Tape.new
    Z::Output.new(tape, telnet: true).emit("\xFF".b)
    assert_equal "\xFF\xFF".b, tape.bytes
  end

  def test_restarts_are_limited
    receiver = StubbornReceiver.new
    assert_raises(Z::Cancelled) { stream(receiver).send_file(''.b, 0) }
  end

  def test_bytes_sent_are_limited
    receiver = StubbornReceiver.new
    data     = 'x' * 10_000
    assert_raises(Z::Cancelled) { stream(receiver).send_file(data, 0) }
    assert_operator receiver.sent, :<, (Z::BUDGET_FACTOR + 1) * data.bytesize * 2
  end
end
